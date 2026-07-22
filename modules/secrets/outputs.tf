output "jwt_secret_arn" {
  value = aws_secretsmanager_secret.jwt.arn
}

output "oidc_client_secret_arn" {
  value = aws_secretsmanager_secret.oidc_client.arn
}

output "admin_write_key_arn" {
  value = aws_secretsmanager_secret.admin_write_key.arn
}

output "console_session_secret_arn" {
  value = aws_secretsmanager_secret.console_session.arn
}

output "postgres_url_secret_arn" {
  value = var.postgres_url.secret_arn
}
