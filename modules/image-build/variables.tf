variable "name_prefix" {
  type = string
}

variable "app_dir" {
  description = "Path to the container build context root (contains gateway/ and, optionally, admin-console/)."
  type        = string
}

variable "build_admin_console" {
  description = "Also build and push the admin console image."
  type        = bool
  default     = true
}

variable "codebuild_image" {
  description = "CodeBuild x86_64 build image. Must be an x86_64 image -- the gateway Dockerfile downloads an x86_64-only claude binary."
  type        = string
  default     = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
}
