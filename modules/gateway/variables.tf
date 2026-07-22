variable "name_prefix" { type = string }
variable "service_name" { type = string }
variable "region" { type = string }
variable "partition" { type = string }
variable "account_id" { type = string }

variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "task_security_group" { type = string }

variable "image_uri" {
  description = "Fully-qualified ECR image URI (repo:tag) the gateway runs."
  type        = string
}

variable "oidc_issuer" { type = string }
variable "oidc_client_id" { type = string }
variable "admin_okta_group" { type = string }

variable "available_models_raw" {
  description = "YAML flow-sequence string, e.g. \"[claude-opus-4-8, claude-sonnet-4-6]\"."
  type        = string
}

variable "oidc_scopes" {
  description = "OIDC scopes the gateway requests. Cognito uses [openid, profile, email]; external OIDC IdPs may add offline_access and groups."
  type        = list(string)
  default     = ["openid", "profile", "email"]
}

variable "jwt_secret_arn" { type = string }
variable "oidc_client_secret_arn" { type = string }
variable "postgres_url_secret_arn" { type = string }
variable "admin_write_key_arn" { type = string }

variable "cpu" { type = string }
variable "memory" { type = string }
variable "log_retention_days" { type = number }
