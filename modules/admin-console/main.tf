terraform {
  required_providers {
    aws   = { source = "hashicorp/aws" }
    awscc = { source = "hashicorp/awscc" }
  }
}

# The admin console (== ClaudeGatewayAdminConsoleStack): spend-limit and
# model-access management, deployed on PUBLIC subnets -- deliberately, since
# it is gated by IdP group membership (checked by the gateway on every admin
# API call), not by network placement, so admins don't need VPN access.
#
# Every spend-limit call the console makes uses the signed-in admin's own
# gateway-issued bearer token, so those changes audit as oidc:<sub> in the
# gateway's own log -- the console holds no gateway credential of its own.
# Model-access is the exception: the console changes it by calling
# ecs:UpdateExpressGatewayService on the GATEWAY's service directly (its only
# runtime-mutable path), so model changes are visible in CloudTrail attributed
# to this task role rather than in the gateway's audit log.

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
  name_prefix        = "${var.name_prefix}-console-exec-"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  description        = "ECS task execution role for the admin console: pulls the image and injects the session secret"
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:${var.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  statement {
    sid       = "ReadSessionSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.session_secret_arn]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# --- Task role (manage the gateway's model catalog; read Bedrock catalog) ---
resource "aws_iam_role" "task" {
  name_prefix        = "${var.name_prefix}-console-task-"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  description        = "Lets the admin console manage the gateway's model catalog via ECS parameters; holds no gateway credential"
}

data "aws_iam_policy_document" "task" {
  statement {
    sid       = "ManageGatewayModelConfig"
    actions   = ["ecs:UpdateExpressGatewayService", "ecs:DescribeExpressGatewayService"]
    resources = [var.gateway_service_arn]
  }

  # UpdateExpressGatewayService registers a new task-definition revision
  # internally, so RegisterTaskDefinition + PassRole on the gateway's own
  # roles are required or the call fails with AccessDenied.
  statement {
    sid       = "RegisterGatewayTaskDefinition"
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = ["arn:${var.partition}:ecs:${var.region}:${var.account_id}:task-definition/${var.gateway_task_definition_family}:*"]
  }

  # ecs:DescribeTaskDefinition does not support resource-level restriction.
  statement {
    sid       = "DescribeGatewayTaskDefinition"
    actions   = ["ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid       = "PassGatewayRoles"
    actions   = ["iam:PassRole"]
    resources = [var.gateway_task_role_arn, var.gateway_execution_role_arn]
  }

  # Show the live Bedrock model catalog rather than a hardcoded list.
  statement {
    sid       = "ReadBedrockCatalog"
    actions   = ["bedrock:ListFoundationModels"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task" {
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}

# --- Infrastructure role ---
resource "aws_iam_role" "infrastructure" {
  name_prefix        = "${var.name_prefix}-console-infra-"
  assume_role_policy = data.aws_iam_policy_document.ecs_service_assume.json
  description        = "Lets ECS Express Mode provision the ALB, target group, SGs, and autoscaling for the admin console"
}

resource "aws_iam_role_policy_attachment" "infrastructure_managed" {
  role       = aws_iam_role.infrastructure.name
  policy_arn = "arn:${var.partition}:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
}

resource "aws_cloudwatch_log_group" "console" {
  name_prefix       = "/ecs/${var.service_name}-"
  retention_in_days = var.log_retention_days
}

locals {
  environment = [
    { name = "GATEWAY_BASE_URL", value = "https://${var.gateway_endpoint}" },
    { name = "GATEWAY_SERVICE_ARN", value = var.gateway_service_arn },
    { name = "AWS_REGION", value = var.region },
  ]
  secrets = [
    { name = "SESSION_SECRET_KEY", value_from = var.session_secret_arn },
  ]
}

resource "awscc_ecs_express_gateway_service" "this" {
  service_name            = var.service_name
  execution_role_arn      = aws_iam_role.execution.arn
  task_role_arn           = aws_iam_role.task.arn
  infrastructure_role_arn = aws_iam_role.infrastructure.arn
  cpu                     = var.cpu
  memory                  = var.memory
  health_check_path       = "/healthz"

  network_configuration = {
    subnets         = var.public_subnet_ids
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
      log_group         = aws_cloudwatch_log_group.console.name
      log_stream_prefix = "ecs"
    }
    environment = concat(
      [{ name = "PUBLIC_URL", value = "https://placeholder.invalid" }],
      local.environment,
    )
    secrets = local.secrets
  }

  lifecycle {
    # Same rationale as the gateway module: PUBLIC_URL is patched post-create
    # by url_fixer. Roll a new image with `make redeploy-console`.
    ignore_changes = [primary_container]
  }
}

resource "terraform_data" "url_fixer" {
  triggers_replace = {
    endpoint = awscc_ecs_express_gateway_service.this.endpoint
    image    = var.image_uri
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash"]
    command     = "${path.module}/../gateway/url-fixer.sh"
    environment = {
      AWS_REGION  = var.region
      SERVICE_ARN = awscc_ecs_express_gateway_service.this.service_arn
      PRIMARY_CONTAINER_JSON = jsonencode({
        Image         = var.image_uri
        ContainerPort = 8080
        AwsLogsConfiguration = {
          LogGroup        = aws_cloudwatch_log_group.console.name
          LogStreamPrefix = "ecs"
        }
        Environment = concat(
          [{ Name = "PUBLIC_URL", Value = "https://${awscc_ecs_express_gateway_service.this.endpoint}" }],
          [for e in local.environment : { Name = e.name, Value = e.value }],
        )
        Secrets = [for s in local.secrets : { Name = s.name, ValueFrom = s.value_from }]
      })
    }
  }
}
