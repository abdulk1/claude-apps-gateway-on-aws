terraform {
  required_providers {
    aws   = { source = "hashicorp/aws" }
    awscc = { source = "hashicorp/awscc" }
  }
}

# The Claude apps gateway itself (== ClaudeGatewayStack), an ECS Express Mode
# service on the PRIVATE subnets. Express Mode derives public-vs-private
# ingress from subnet routing, so private subnets => an internal load
# balancer, satisfying the "deploy on your private network" requirement.
#
# Three IAM roles are required (Express Mode's create API needs the
# infrastructure role in addition to the usual execution + task roles):
#   - execution: pulls the image, injects the secrets as env vars.
#   - task:      what the gateway PROCESS can call -- Bedrock invoke only.
#   - infrastructure: what Express Mode uses to provision the ALB, target
#     group, security groups, and autoscaling on your behalf.

########################################
# IAM
########################################

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_service_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

# --- Execution role ---
resource "aws_iam_role" "execution" {
  name_prefix        = "${var.name_prefix}-gw-exec-"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  description        = "ECS task execution role for the Claude gateway: pulls the image and injects secrets"
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${var.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  statement {
    sid     = "ReadGatewaySecrets"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      var.jwt_secret_arn,
      var.oidc_client_secret_arn,
      var.postgres_url_secret_arn,
      var.admin_write_key_arn,
    ]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# --- Task role (Bedrock invoke only) ---
resource "aws_iam_role" "task" {
  name_prefix        = "${var.name_prefix}-gw-task-"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  description        = "What the gateway process itself can call: Bedrock model invocation only"
}

data "aws_iam_policy_document" "task_bedrock" {
  statement {
    sid     = "BedrockInvokeClaudeModels"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = [
      "arn:${var.partition}:bedrock:${var.region}:${var.account_id}:inference-profile/us.anthropic.*",
      "arn:${var.partition}:bedrock:*::foundation-model/anthropic.*",
    ]
  }

  # Covers any custom application inference profile you add to gateway.yaml's
  # models: block (docs/06-custom-inference-profile.md). Scoped to this
  # account's own profiles in any region, so adding YAML entries later needs
  # no IAM change.
  statement {
    sid     = "BedrockInvokeCustomInferenceProfiles"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = [
      "arn:${var.partition}:bedrock:*:${var.account_id}:application-inference-profile/*",
      "arn:${var.partition}:bedrock:*::foundation-model/anthropic.*",
    ]
  }
}

resource "aws_iam_role_policy" "task_bedrock" {
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_bedrock.json
}

# --- Infrastructure role (Express Mode provisions the ALB etc. as this) ---
resource "aws_iam_role" "infrastructure" {
  name_prefix        = "${var.name_prefix}-gw-infra-"
  assume_role_policy = data.aws_iam_policy_document.ecs_service_assume.json
  description        = "Lets ECS Express Mode provision the ALB, target group, SGs, and autoscaling for the gateway"
}

resource "aws_iam_role_policy_attachment" "infrastructure_managed" {
  role       = aws_iam_role.infrastructure.name
  policy_arn = "arn:${var.partition}:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
}

########################################
# Logs
########################################

resource "aws_cloudwatch_log_group" "gateway" {
  name_prefix       = "/ecs/${var.service_name}-"
  retention_in_days = var.log_retention_days
}

########################################
# Container spec
#
# Defined once as a local. The awscc resource gets it with a PLACEHOLDER
# public URL (the real endpoint is unknowable until the service exists); the
# url_fixer below re-applies the same spec with the real URL substituted.
########################################

locals {
  environment = [
    { name = "OIDC_ISSUER", value = var.oidc_issuer },
    { name = "OIDC_CLIENT_ID", value = var.oidc_client_id },
    { name = "ADMIN_OKTA_GROUP_NAME", value = var.admin_okta_group },
    { name = "AWS_REGION", value = var.region },
    # Substituted into gateway.yaml's oidc.scopes at container start by
    # entrypoint.sh (a YAML flow sequence, like AVAILABLE_MODELS_RAW).
    { name = "OIDC_SCOPES_RAW", value = format("[%s]", join(", ", var.oidc_scopes)) },
    # Substituted into gateway.yaml at container start by entrypoint.sh; the
    # admin console changes this later via a plain ECS parameter update.
    { name = "AVAILABLE_MODELS_RAW", value = var.available_models_raw },
  ]

  secrets = [
    { name = "OIDC_CLIENT_SECRET", value_from = var.oidc_client_secret_arn },
    { name = "GATEWAY_JWT_SECRET", value_from = var.jwt_secret_arn },
    { name = "GATEWAY_POSTGRES_URL", value_from = var.postgres_url_secret_arn },
    { name = "GATEWAY_ADMIN_WRITE_KEY", value_from = var.admin_write_key_arn },
  ]
}

########################################
# ECS Express Mode service (awscc -- tracks AWS::ECS::ExpressGatewayService)
########################################

resource "awscc_ecs_express_gateway_service" "this" {
  service_name            = var.service_name
  execution_role_arn      = aws_iam_role.execution.arn
  task_role_arn           = aws_iam_role.task.arn
  infrastructure_role_arn = aws_iam_role.infrastructure.arn
  cpu                     = var.cpu
  memory                  = var.memory
  health_check_path       = "/healthz"

  network_configuration = {
    subnets         = var.private_subnet_ids
    security_groups = [var.task_security_group]
  }

  scaling_target = {
    min_task_count            = 1
    max_task_count            = 2
    auto_scaling_metric       = "AVERAGE_CPU"
    auto_scaling_target_value = 60
  }

  primary_container = {
    image          = var.image_uri
    container_port = 8080
    aws_logs_configuration = {
      log_group         = aws_cloudwatch_log_group.gateway.name
      log_stream_prefix = "ecs"
    }
    # Placeholder; corrected in place by terraform_data.url_fixer once the
    # real endpoint is known.
    environment = concat(
      [{ name = "GATEWAY_PUBLIC_URL", value = "https://placeholder.invalid" }],
      local.environment,
    )
    secrets = local.secrets
  }

  lifecycle {
    # After creation the primary container is managed outside Terraform, by
    # design: the public URL is patched by url_fixer below, and the model
    # catalog (AVAILABLE_MODELS_RAW) is changed by the admin console via an
    # ECS parameter update. Ignoring it keeps those out-of-band, intended
    # changes from showing as perpetual drift. Roll a new image with
    # `make redeploy-gateway` (see the Makefile) or by tainting this resource.
    ignore_changes = [primary_container]
  }
}

########################################
# Post-create URL fix (== the CDK GatewayUrlFixer custom resource)
#
# Express Mode's ingress hostname is unpredictable and known only after the
# service exists. This re-applies the primary container with the REAL public
# URL substituted, via `aws ecs update-express-gateway-service`. It re-runs
# whenever the endpoint or the image changes, so image rollouts flow through
# here too. Requires the AWS CLI + jq on the machine running terraform.
########################################

resource "terraform_data" "url_fixer" {
  triggers_replace = {
    endpoint = awscc_ecs_express_gateway_service.this.endpoint
    image    = var.image_uri
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash"]
    command     = "${path.module}/url-fixer.sh"
    environment = {
      AWS_REGION  = var.region
      SERVICE_ARN = awscc_ecs_express_gateway_service.this.service_arn
      # The full desired primary container, with the real public URL, as the
      # ECS UpdateExpressGatewayService API expects it (PascalCase members).
      PRIMARY_CONTAINER_JSON = jsonencode({
        Image         = var.image_uri
        ContainerPort = 8080
        AwsLogsConfiguration = {
          LogGroup        = aws_cloudwatch_log_group.gateway.name
          LogStreamPrefix = "ecs"
        }
        Environment = concat(
          [{ Name = "GATEWAY_PUBLIC_URL", Value = "https://${awscc_ecs_express_gateway_service.this.endpoint}" }],
          [for e in local.environment : { Name = e.name, Value = e.value }],
        )
        Secrets = [for s in local.secrets : { Name = s.name, ValueFrom = s.value_from }]
      })
    }
  }
}
