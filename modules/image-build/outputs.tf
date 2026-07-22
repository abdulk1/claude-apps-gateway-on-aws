output "gateway_image_uri" {
  description = "Gateway image URI (repo:tag). Reading this implies the CodeBuild build has completed."
  value       = terraform_data.build.output.gateway_image_uri
}

output "admin_console_image_uri" {
  description = "Admin console image URI (repo:tag), or null when not built."
  value       = terraform_data.build.output.admin_console_image_uri
}

output "gateway_repository_url" {
  value = aws_ecr_repository.gateway.repository_url
}

output "codebuild_project_name" {
  value = aws_codebuild_project.images.name
}
