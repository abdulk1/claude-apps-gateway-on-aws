# Claude Apps Gateway on AWS -- Terraform root module.
#
# A faithful port of the aws-samples CDK reference architecture
# (https://github.com/aws-samples/sample-claude-apps-gateway-on-aws), fronting
# Amazon Bedrock with the Anthropic Claude apps gateway plus an admin console.
#
# The seven CDK stacks map onto the modules below. Because this is a single,
# self-contained deployment (one VPC, one Aurora cluster, two ECS Express Mode
# services), the modules are wired with direct references rather than
# cross-stack exports -- the same rationale the CDK app documents.
#
# What deviates from the CDK sample, and why, is documented per-module below
# and in docs/differences-from-cdk-sample.md.

########################################
# Network  (== ClaudeGatewayNetworkStack)
########################################
module "network" {
  source = "./modules/network"

  name_prefix = var.name_prefix
  vpc_cidr    = var.vpc_cidr
  region      = local.region
}

########################################
# Database  (== ClaudeGatewayDatabaseStack)
#
# Aurora Serverless v2 PostgreSQL. The CDK used a Lambda custom resource to
# compose the postgres_url from RDS's own managed credentials without leaking
# it into the template; here the master password is a random_password and the
# URL is composed directly in Terraform (no Lambda). The tradeoff -- the
# password lives in Terraform state -- is why backend.tf insists on encrypted
# remote state.
########################################
module "database" {
  source = "./modules/database"

  name_prefix              = var.name_prefix
  vpc_id                   = module.network.vpc_id
  private_subnet_ids       = module.network.private_subnet_ids
  database_security_group  = module.network.database_security_group_id
  min_capacity             = var.aurora_min_capacity
  max_capacity             = var.aurora_max_capacity
  seconds_until_auto_pause = var.aurora_seconds_until_auto_pause
}

########################################
# Identity provider
#
# Default: Cognito user pool as the OIDC bridge in front of IAM Identity Center
# (SAML). The gateway is OIDC-only ("Front with an OIDC bridge if needed" --
# code.claude.com docs), so Identity Center sits behind Cognito. Set
# enable_cognito_idp = false to use an external OIDC IdP (Okta) via the
# oidc_* variables instead.
########################################

# Fail fast if using an external IdP without its config.
resource "terraform_data" "idp_guard" {
  lifecycle {
    precondition {
      condition     = var.enable_cognito_idp || (var.oidc_issuer != null && var.oidc_client_id != null && var.oidc_client_secret != null)
      error_message = "enable_cognito_idp = false requires oidc_issuer, oidc_client_id, and oidc_client_secret to be set."
    }
  }
}

module "idp_cognito" {
  source = "./modules/idp-cognito"
  count  = var.enable_cognito_idp ? 1 : 0

  name_prefix                       = var.name_prefix
  region                            = local.region
  admin_group_name                  = var.admin_okta_group_name
  domain_prefix                     = var.cognito_domain_prefix
  identity_center_saml_metadata_url = var.identity_center_saml_metadata_url
  saml_email_attribute              = var.saml_email_attribute
  saml_groups_attribute             = var.saml_groups_attribute
}

########################################
# Secrets  (== ClaudeGatewaySecretsStack)
########################################
module "secrets" {
  source = "./modules/secrets"

  name_prefix        = var.name_prefix
  oidc_client_secret = local.effective_oidc_client_secret
  postgres_url       = module.database.postgres_url
}

########################################
# Image build  (== ClaudeGatewayBuildMachineStack)
#
# The CDK spun up a temporary x86_64 EC2 instance driven by SSM to build the
# images (the gateway Dockerfile downloads an x86_64-only claude binary). Here
# that is a managed CodeBuild project on an x86_64 build image -- no instance
# to provision, wait for, or tear down. Images are tagged by source-content
# hash so a source change forces a new immutable tag (and an ECS redeploy).
########################################
module "image_build" {
  source = "./modules/image-build"

  name_prefix         = var.name_prefix
  app_dir             = "${path.root}/app"
  build_admin_console = var.enable_admin_console
}

########################################
# Gateway  (== ClaudeGatewayStack)  -- private subnets, internal ALB
########################################
module "gateway" {
  source = "./modules/gateway"

  name_prefix  = var.name_prefix
  service_name = local.gateway_service_name
  region       = local.region
  partition    = local.partition
  account_id   = local.account_id

  vpc_id              = module.network.vpc_id
  private_subnet_ids  = module.network.private_subnet_ids
  task_security_group = module.network.gateway_task_security_group_id

  image_uri = module.image_build.gateway_image_uri

  oidc_issuer          = local.effective_oidc_issuer
  oidc_client_id       = local.effective_oidc_client_id
  oidc_scopes          = local.oidc_scopes
  admin_okta_group     = var.admin_okta_group_name
  available_models_raw = local.available_models_raw

  jwt_secret_arn          = module.secrets.jwt_secret_arn
  oidc_client_secret_arn  = module.secrets.oidc_client_secret_arn
  postgres_url_secret_arn = module.secrets.postgres_url_secret_arn
  admin_write_key_arn     = module.secrets.admin_write_key_arn

  cpu                = var.service_cpu
  memory             = var.service_memory
  log_retention_days = var.log_retention_days
}

########################################
# Admin console  (== ClaudeGatewayAdminConsoleStack)  -- public subnets
########################################
module "admin_console" {
  source = "./modules/admin-console"
  count  = var.enable_admin_console ? 1 : 0

  name_prefix  = var.name_prefix
  service_name = local.console_service_name
  region       = local.region
  partition    = local.partition
  account_id   = local.account_id

  public_subnet_ids   = module.network.public_subnet_ids
  task_security_group = module.network.admin_console_security_group_id

  image_uri = module.image_build.admin_console_image_uri

  gateway_service_arn            = module.gateway.service_arn
  gateway_endpoint               = module.gateway.endpoint
  gateway_task_role_arn          = module.gateway.task_role_arn
  gateway_execution_role_arn     = module.gateway.execution_role_arn
  gateway_task_definition_family = local.gateway_task_definition_family

  session_secret_arn = module.secrets.console_session_secret_arn

  cpu                = var.service_cpu
  memory             = var.service_memory
  log_retention_days = var.log_retention_days
}

########################################
# VPN  (== ClaudeGatewayVpnStack)  -- self-service mutual-TLS Client VPN
#
# The CDK generated the full CA/server/client cert chain inside two Lambda
# custom resources and assembled the .ovpn by hand. Here the tls provider
# generates the chain and the .ovpn is rendered from a template -- no Lambdas.
########################################
module "vpn" {
  source = "./modules/vpn"
  count  = var.enable_vpn ? 1 : 0

  name_prefix        = var.name_prefix
  region             = local.region
  vpc_id             = module.network.vpc_id
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = module.network.private_subnet_ids
  client_cidr        = var.vpn_client_cidr
}

########################################
# Cognito callback fix (two-pass, like the gateway URL fixer)
#
# The gateway's OIDC redirect URI is https://<gateway-endpoint>/oauth/callback,
# unknowable when the Cognito app client is created. This patches the client's
# callback URL once the gateway endpoint exists. Requires the AWS CLI.
########################################
resource "terraform_data" "cognito_callback_fixer" {
  count = var.enable_cognito_idp ? 1 : 0

  triggers_replace = {
    endpoint  = module.gateway.endpoint
    client_id = module.idp_cognito[0].app_client_id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash"]
    command     = "${path.root}/scripts/cognito-callback-fixer.sh"
    environment = {
      AWS_REGION     = local.region
      USER_POOL_ID   = module.idp_cognito[0].user_pool_id
      CLIENT_ID      = module.idp_cognito[0].app_client_id
      CALLBACK_URL   = "https://${module.gateway.endpoint}/oauth/callback"
      SUPPORTED_IDPS = join(" ", module.idp_cognito[0].supported_identity_providers)
    }
  }
}
