output "cluster_endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "postgres_url" {
  description = "Object describing the composed postgres_url secret (ARN passed to the secrets module)."
  value = {
    secret_arn = aws_secretsmanager_secret.postgres_url.arn
    version_id = aws_secretsmanager_secret_version.postgres_url.version_id
  }
}
