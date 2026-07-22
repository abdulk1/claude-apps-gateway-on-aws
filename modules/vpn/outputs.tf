output "endpoint_id" {
  value = aws_ec2_client_vpn_endpoint.this.id
}

output "client_profile_secret_arn" {
  value = aws_secretsmanager_secret.client_profile.arn
}

output "endpoint_dns" {
  value = local.endpoint_dns
}
