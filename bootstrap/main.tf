# CI bootstrap: GitHub Actions OIDC provider + a read-only role for
# `terraform plan` in .github/workflows/terraform.yml.
#
# This is a SEPARATE Terraform root with its own state -- it must exist before
# CI can run, so it can't live in the main config that CI plans. Apply it once
# with admin credentials:
#
#   cd bootstrap
#   AWS_PROFILE=claude-gateway terraform init
#   AWS_PROFILE=claude-gateway terraform apply
#   terraform output -raw ci_plan_role_arn   # -> set as the AWS_PLAN_ROLE_ARN repo variable
#
# The role is keyless (OIDC, no long-lived secrets) and read-only (plan only).
# Its trust is scoped to this repo's pull_request and main-branch workflows.

terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Uses the default credential chain -- run with AWS_PROFILE set to an admin
  # SSO profile (e.g. AWS_PROFILE=claude-gateway).
  default_tags {
    tags = {
      Project   = "claude-apps-gateway"
      ManagedBy = "terraform-bootstrap"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_repo" {
  description = "owner/repo allowed to assume the CI role."
  type        = string
  default     = "abdulk1/claude-apps-gateway-on-aws"
}

variable "role_name" {
  type    = string
  default = "claude-gateway-ci-plan"
}

data "aws_partition" "current" {}

# GitHub's OIDC discovery cert -> thumbprint (fetched dynamically rather than
# pinned to a value that eventually rotates).
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only this repo's PR and main-branch runs -- not forks, not other refs.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:pull_request",
        "repo:${var.github_repo}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "ci_plan" {
  name               = var.role_name
  description        = "GitHub Actions OIDC role for read-only `terraform plan` on ${var.github_repo}."
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

# Plan only reads (data sources, refresh) -- ReadOnlyAccess is sufficient and
# can't mutate anything. Grant broader perms only if you later add a CI apply.
resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.ci_plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

output "ci_plan_role_arn" {
  value = aws_iam_role.ci_plan.arn
}

output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}
