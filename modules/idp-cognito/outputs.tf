output "issuer" {
  description = "OIDC issuer for the gateway's oidc.issuer (serves /.well-known/openid-configuration)."
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
}

output "client_id" {
  value = aws_cognito_user_pool_client.gateway.id
}

output "client_secret" {
  value     = aws_cognito_user_pool_client.gateway.client_secret
  sensitive = true
}

output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "app_client_id" {
  value = aws_cognito_user_pool_client.gateway.id
}

output "supported_identity_providers" {
  value = local.supported_idps
}

output "hosted_ui_domain" {
  description = "Cognito hosted-UI domain."
  value       = local.hosted_domain
}

# --- Values to enter when creating the IAM Identity Center SAML application ---

output "saml_acs_url" {
  description = "Identity Center app: Assertion Consumer Service (ACS) URL / SAML reply URL."
  value       = local.saml_acs_url
}

output "saml_entity_id" {
  description = "Identity Center app: Application SAML audience / entity ID."
  value       = local.saml_entity_id
}

output "saml_federation_active" {
  description = "True once identity_center_saml_metadata_url is set and the SAML IdP is wired up (phase 2)."
  value       = local.create_saml
}
