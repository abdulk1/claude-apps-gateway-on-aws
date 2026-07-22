variable "name_prefix" { type = string }
variable "region" { type = string }

variable "admin_group_name" {
  description = "Group name that grants gateway admin rights. Must match the group name IAM Identity Center sends in the SAML groups attribute (surfaced to the gateway as the `groups` claim by the pre-token Lambda)."
  type        = string
}

variable "domain_prefix" {
  description = "Cognito hosted-UI domain prefix (globally unique). Defaults to name_prefix + a random suffix."
  type        = string
  default     = null
}

variable "identity_center_saml_metadata_url" {
  description = "SAML metadata URL of the IAM Identity Center customer-managed application (from the Identity Center app you create — see docs/01-prerequisites.md). Leave null on the FIRST apply (bootstrap: pool + domain get created so you can configure the Identity Center app), then set it and apply again to wire up federation."
  type        = string
  default     = null
}

variable "saml_email_attribute" {
  description = "Name of the email attribute in the Identity Center SAML assertion, mapped to the Cognito email attribute."
  type        = string
  default     = "email"
}

variable "saml_groups_attribute" {
  description = "Name of the group-membership attribute in the Identity Center SAML assertion, mapped to Cognito custom:groups and then to the gateway's `groups` claim."
  type        = string
  default     = "groups"
}

variable "callback_urls" {
  description = "OAuth callback URLs for the gateway app client. Seeded with a placeholder; the real https://<gateway-endpoint>/oauth/callback is patched in by the root cognito_callback_fixer once the gateway endpoint is known."
  type        = list(string)
  default     = ["https://placeholder.invalid/oauth/callback"]
}

variable "lambda_runtime" {
  type    = string
  default = "python3.12"
}
