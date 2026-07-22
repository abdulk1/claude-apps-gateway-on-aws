output "gateway_endpoint" {
  description = "The gateway's ECS Express Mode ingress hostname (private). Set forceLoginGatewayUrl to https://<this> in managed-settings.json on developer machines -- see docs/03-verify.md."
  value       = "https://${module.gateway.endpoint}"
}

output "gateway_service_arn" {
  description = "ARN of the gateway ECS Express Mode service."
  value       = module.gateway.service_arn
}

output "admin_console_endpoint" {
  description = "The admin console URL. Publicly reachable; access is gated by IdP group membership, not network placement. Null when enable_admin_console = false."
  value       = var.enable_admin_console ? module.admin_console[0].endpoint : null
}

output "gateway_image_uri" {
  description = "Fully-qualified ECR image URI (tagged by source hash) the gateway service runs."
  value       = module.image_build.gateway_image_uri
}

output "admin_console_image_uri" {
  description = "Fully-qualified ECR image URI the admin console service runs. Null when the admin console is not built."
  value       = module.image_build.admin_console_image_uri
}

output "oidc_client_secret_arn" {
  description = "ARN of the gateway's OIDC client secret (for rotation/lookup). The value itself is never output."
  value       = module.secrets.oidc_client_secret_arn
}

output "vpn_endpoint_id" {
  description = "AWS Client VPN endpoint ID. Null when enable_vpn = false."
  value       = var.enable_vpn ? module.vpn[0].endpoint_id : null
}

output "vpn_client_profile_secret_arn" {
  description = <<-EOT
    ARN of the Secrets Manager secret holding the ready-to-import .ovpn profile.
    Download with:
      aws secretsmanager get-secret-value --secret-id <arn> \
        --query SecretString --output text | jq -r .ovpnProfile > claude-gateway-vpn.ovpn
    Null when enable_vpn = false.
  EOT
  value       = var.enable_vpn ? module.vpn[0].client_profile_secret_arn : null
}

output "oidc_issuer" {
  description = "Effective OIDC issuer the gateway uses (the Cognito user pool, or your external IdP)."
  value       = local.effective_oidc_issuer
}

# --- Cognito / IAM Identity Center (null when enable_cognito_idp = false) ---

output "cognito_user_pool_id" {
  value = var.enable_cognito_idp ? module.idp_cognito[0].user_pool_id : null
}

output "cognito_hosted_ui_domain" {
  value = var.enable_cognito_idp ? module.idp_cognito[0].hosted_ui_domain : null
}

output "identity_center_saml_acs_url" {
  description = "Enter this as the ACS URL / SAML reply URL when creating the IAM Identity Center customer-managed SAML application (see docs/01-prerequisites.md)."
  value       = var.enable_cognito_idp ? module.idp_cognito[0].saml_acs_url : null
}

output "identity_center_saml_entity_id" {
  description = "Enter this as the application SAML audience / entity ID in the IAM Identity Center app."
  value       = var.enable_cognito_idp ? module.idp_cognito[0].saml_entity_id : null
}

output "cognito_saml_federation_active" {
  description = "False until you set identity_center_saml_metadata_url and re-apply (phase 2)."
  value       = var.enable_cognito_idp ? module.idp_cognito[0].saml_federation_active : null
}

output "admin_okta_group_name" {
  description = "Configured admin group name (echoed for cross-checking against your IdP)."
  value       = var.admin_okta_group_name
}

output "name_prefix" {
  description = "Resource name prefix (handy for scripting secret/resource lookups)."
  value       = var.name_prefix
}
