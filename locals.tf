data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = var.aws_region

  # ECS Express Mode derives the task-definition family name as
  # "default-${serviceName}" (confirmed in the CDK sample against a real
  # deployment), so these two names drive every IAM policy that has to
  # reference the resulting task-definition family.
  gateway_service_name = "${var.name_prefix}-gateway"
  console_service_name = "${var.name_prefix}-console"

  gateway_task_definition_family = "default-${local.gateway_service_name}"
  console_task_definition_family = "default-${local.console_service_name}"

  # YAML flow-sequence string substituted into gateway.yaml at container
  # start by app/gateway/entrypoint.sh, e.g. "[claude-opus-4-8, claude-sonnet-4-6]".
  available_models_raw = format("[%s]", join(", ", var.available_models))

  # Effective OIDC config: from the Cognito bridge module, or external IdP vars.
  effective_oidc_issuer        = var.enable_cognito_idp ? module.idp_cognito[0].issuer : var.oidc_issuer
  effective_oidc_client_id     = var.enable_cognito_idp ? module.idp_cognito[0].client_id : var.oidc_client_id
  effective_oidc_client_secret = var.enable_cognito_idp ? module.idp_cognito[0].client_secret : var.oidc_client_secret

  # Cognito rejects the `groups` and `offline_access` scopes (groups arrive via
  # the pre-token `groups` claim; refresh tokens don't need offline_access).
  # External OIDC IdPs (Okta) use the fuller list.
  oidc_scopes = var.enable_cognito_idp ? ["openid", "profile", "email"] : ["openid", "profile", "email", "offline_access", "groups"]
}
