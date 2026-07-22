output "service_arn" {
  value = awscc_ecs_express_gateway_service.this.service_arn
}

output "endpoint" {
  description = "The gateway's ECS Express Mode ingress hostname (no scheme)."
  value       = awscc_ecs_express_gateway_service.this.endpoint
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.gateway.name
}
