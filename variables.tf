########################################
# Core deployment
########################################

variable "aws_region" {
  description = "AWS region to deploy into. Must be a region where Amazon Bedrock and ECS Express Mode are available."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix applied to resource names. Kept short and lowercase; used to derive the ECS Express Mode service names (which must be unique per account/region)."
  type        = string
  default     = "claude-gateway"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,24}$", var.name_prefix))
    error_message = "name_prefix must be 2-25 chars, lowercase alphanumeric or hyphen, starting with a letter."
  }
}

variable "tags" {
  description = "Additional tags applied to every resource via the aws provider default_tags."
  type        = map(string)
  default     = {}
}

########################################
# Identity provider
#
# Default: a Cognito user pool acting as the OIDC bridge in front of IAM
# Identity Center (SAML) -- the gateway is OIDC-only, so Identity Center sits
# behind Cognito. Set enable_cognito_idp = false to instead point the gateway
# at an external OIDC IdP (Okta etc.) via oidc_issuer/oidc_client_id/
# oidc_client_secret below. See docs/01-prerequisites.md.
########################################

variable "enable_cognito_idp" {
  description = "Provision a Cognito user pool (OIDC bridge) federated to IAM Identity Center via SAML, and source the gateway's OIDC config from it. When false, provide oidc_issuer/oidc_client_id/oidc_client_secret for an external OIDC IdP instead."
  type        = bool
  default     = true
}

variable "identity_center_saml_metadata_url" {
  description = "SAML metadata URL of the IAM Identity Center customer-managed application. Leave null on the first apply (bootstrap creates the Cognito pool + domain so you can configure the Identity Center app), then set it and apply again. Only used when enable_cognito_idp = true."
  type        = string
  default     = null
}

variable "cognito_domain_prefix" {
  description = "Cognito hosted-UI domain prefix (globally unique). Defaults to name_prefix + a random suffix. Only used when enable_cognito_idp = true."
  type        = string
  default     = null
}

variable "saml_email_attribute" {
  description = "Name of the email attribute in the Identity Center SAML assertion."
  type        = string
  default     = "email"
}

variable "saml_groups_attribute" {
  description = "Name of the group-membership attribute in the Identity Center SAML assertion (mapped to the gateway's `groups` claim via the pre-token Lambda)."
  type        = string
  default     = "groups"
}

# --- External OIDC IdP (only when enable_cognito_idp = false) ---

variable "oidc_issuer" {
  description = "OIDC issuer URL for an external IdP (e.g. https://your-org.okta.com). Only used when enable_cognito_idp = false."
  type        = string
  default     = null

  validation {
    condition     = var.oidc_issuer == null || can(regex("^https://", var.oidc_issuer))
    error_message = "oidc_issuer must be an https:// URL."
  }
}

variable "oidc_client_id" {
  description = "OAuth client ID from your external IdP app registration. Only used when enable_cognito_idp = false."
  type        = string
  default     = null
}

variable "oidc_client_secret" {
  description = "OAuth client secret from your external IdP app registration. Only used when enable_cognito_idp = false; provide via TF_VAR_oidc_client_secret. Written to Secrets Manager, never baked into an image."
  type        = string
  sensitive   = true
  default     = null
}

variable "admin_okta_group_name" {
  description = "Group name whose members get full gateway admin rights. Must match the group name your IdP emits in the `groups` claim (for Cognito+Identity Center, the Identity Center group surfaced via the SAML groups attribute)."
  type        = string
  default     = "claude-gateway-admins"
}

########################################
# Model catalog
########################################

variable "available_models" {
  description = "Claude models exposed to developers by default. Changed at runtime via the admin console (a plain ECS parameter update, no image rebuild), so this is only the initial catalog."
  type        = list(string)
  default     = ["claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5"]
}

########################################
# Feature toggles
########################################

variable "enable_admin_console" {
  description = "Deploy the spend-limit / model-access admin console (public subnets, gated by IdP group membership). Requires the admin-console app source under app/admin-console -- run scripts/fetch-admin-console-source.sh first."
  type        = bool
  default     = true
}

variable "enable_vpn" {
  description = "Deploy the self-service AWS Client VPN endpoint (mutual TLS) developers use to reach the private gateway. Disable if you already have private connectivity into the VPC."
  type        = bool
  default     = true
}

########################################
# Network
########################################

variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpn_client_cidr" {
  description = "CIDR block handed out to connected Client VPN clients. Must not overlap vpc_cidr. Ignored when enable_vpn = false."
  type        = string
  default     = "10.100.0.0/16"
}

########################################
# Sizing / cost
########################################

variable "aurora_min_capacity" {
  description = "Aurora Serverless v2 minimum ACU. 0 allows auto-pause after idle (secondsUntilAutoPause below)."
  type        = number
  default     = 0
}

variable "aurora_max_capacity" {
  description = "Aurora Serverless v2 maximum ACU."
  type        = number
  default     = 4
}

variable "aurora_seconds_until_auto_pause" {
  description = "Idle seconds before Aurora Serverless v2 auto-pauses (only when aurora_min_capacity = 0). 1800 = 30 minutes."
  type        = number
  default     = 1800
}

variable "service_cpu" {
  description = "Fargate CPU units for the gateway and admin console tasks."
  type        = string
  default     = "1024"
}

variable "service_memory" {
  description = "Fargate memory (MiB) for the gateway and admin console tasks."
  type        = string
  default     = "2048"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the gateway and admin console log groups."
  type        = number
  default     = 14
}
