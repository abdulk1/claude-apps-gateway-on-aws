variable "name_prefix" { type = string }
variable "service_name" { type = string }
variable "region" { type = string }
variable "partition" { type = string }
variable "account_id" { type = string }

variable "public_subnet_ids" { type = list(string) }
variable "task_security_group" { type = string }

variable "image_uri" {
  description = "Fully-qualified ECR image URI (repo:tag) the admin console runs."
  type        = string
}

variable "gateway_service_arn" { type = string }
variable "gateway_endpoint" { type = string }
variable "gateway_task_role_arn" { type = string }
variable "gateway_execution_role_arn" { type = string }

variable "gateway_task_definition_family" {
  description = "Gateway task-definition family (default-<gateway service name>) the console updates for model-access changes."
  type        = string
}

variable "session_secret_arn" { type = string }

variable "cpu" { type = string }
variable "memory" { type = string }
variable "log_retention_days" { type = number }
