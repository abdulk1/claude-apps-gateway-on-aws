variable "name_prefix" {
  type = string
}

variable "oidc_client_secret" {
  description = "Real OIDC client secret from the IdP app registration."
  type        = string
  sensitive   = true
}

variable "postgres_url" {
  description = "postgres_url secret object from the database module (re-exported for the gateway)."
  type = object({
    secret_arn = string
    version_id = string
  })
}
