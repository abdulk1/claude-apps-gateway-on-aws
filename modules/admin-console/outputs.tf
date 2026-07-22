output "endpoint" {
  description = "The admin console URL. Publicly reachable; gated by IdP group membership."
  value       = "https://${awscc_ecs_express_gateway_service.this.endpoint}"
}

output "service_arn" {
  value = awscc_ecs_express_gateway_service.this.service_arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}
