terraform {
  required_providers {
    aws     = { source = "hashicorp/aws" }
    archive = { source = "hashicorp/archive" }
    random  = { source = "hashicorp/random" }
  }
}

# Builds and pushes the gateway (and optionally the admin console) container
# images. == ClaudeGatewayBuildMachineStack, but implemented with AWS
# CodeBuild instead of a temporary EC2 instance driven by SSM.
#
# WHY x86_64 matters: the gateway Dockerfile hardcodes PLATFORM="linux-x64"
# when downloading the claude binary, so the image is only correct when built
# ON an x86_64 host. CodeBuild's amazonlinux-x86_64 image gives us that for
# free -- a managed, ephemeral build environment with nothing to provision,
# wait for, or tear down (the CDK sample's EC2 build machine + SSM + Lambda
# poller all collapse into this one project + a start-build call).
#
# Images are tagged by the source-content hash, so a change to anything under
# app/ produces a new immutable tag and forces ECS to redeploy.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_id" "bucket" {
  byte_length = 4
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  source_zip = "${path.module}/.build/app-source.zip"
}

# Zip the whole build context (gateway/, admin-console/). The output hash is
# what drives both the image tag and the rebuild trigger.
data "archive_file" "source" {
  type        = "zip"
  source_dir  = var.app_dir
  output_path = local.source_zip
}

locals {
  image_tag = substr(data.archive_file.source.output_sha256, 0, 12)
}

########################################
# ECR
########################################

resource "aws_ecr_repository" "gateway" {
  name                 = "${var.name_prefix}/gateway"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "admin_console" {
  count                = var.build_admin_console ? 1 : 0
  name                 = "${var.name_prefix}/admin-console"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

########################################
# Source bucket (CodeBuild pulls the build context from here)
########################################

resource "aws_s3_bucket" "source" {
  bucket        = "${var.name_prefix}-codebuild-src-${random_id.bucket.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket                  = aws_s3_bucket.source.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_object" "source" {
  bucket = aws_s3_bucket.source.id
  key    = "app-source-${local.image_tag}.zip"
  source = data.archive_file.source.output_path
  etag   = data.archive_file.source.output_md5
}

########################################
# CodeBuild
########################################

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name_prefix        = "${var.name_prefix}-cb-"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/${var.name_prefix}-*"]
  }

  statement {
    sid       = "SourceBucket"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.source.arn, "${aws_s3_bucket.source.arn}/*"]
  }

  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
    ]
    resources = concat(
      [aws_ecr_repository.gateway.arn],
      aws_ecr_repository.admin_console[*].arn,
    )
  }
}

data "aws_partition" "current" {}

resource "aws_iam_role_policy" "codebuild" {
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild.json
}

resource "aws_codebuild_project" "images" {
  name         = "${var.name_prefix}-image-build"
  description  = "Builds and pushes the Claude gateway (and admin console) container images on an x86_64 host."
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = var.codebuild_image
    type            = "LINUX_CONTAINER"
    privileged_mode = true # required to run the Docker daemon

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = local.account_id
    }
    environment_variable {
      name  = "IMAGE_TAG"
      value = local.image_tag
    }
    environment_variable {
      name  = "GATEWAY_REPO_URI"
      value = aws_ecr_repository.gateway.repository_url
    }
    environment_variable {
      name  = "ADMIN_CONSOLE_REPO_URI"
      value = var.build_admin_console ? aws_ecr_repository.admin_console[0].repository_url : ""
    }
    environment_variable {
      name  = "BUILD_ADMIN_CONSOLE"
      value = var.build_admin_console ? "true" : "false"
    }
  }

  source {
    type      = "S3"
    location  = "${aws_s3_bucket.source.bucket}/${aws_s3_object.source.key}"
    buildspec = file("${path.module}/buildspec.yml")
  }

  logs_config {
    cloudwatch_logs {
      group_name = "/aws/codebuild/${var.name_prefix}-image-build"
    }
  }
}

########################################
# Trigger the build and wait for it to finish.
#
# terraform_data re-runs its provisioner whenever the source hash changes
# (triggers_replace), mirroring the CDK custom resource that rebuilt on every
# deploy. Its `output` (mirroring `input`) is what downstream modules read as
# the image URI -- so referencing it gives them an implicit dependency on the
# build having completed. Requires the AWS CLI on the machine running
# terraform.
########################################
resource "terraform_data" "build" {
  triggers_replace = data.archive_file.source.output_sha256

  input = {
    gateway_image_uri       = "${aws_ecr_repository.gateway.repository_url}:${local.image_tag}"
    admin_console_image_uri = var.build_admin_console ? "${aws_ecr_repository.admin_console[0].repository_url}:${local.image_tag}" : null
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash"]
    command     = "${path.module}/run-build.sh"
    environment = {
      PROJECT_NAME = aws_codebuild_project.images.name
      AWS_REGION   = local.region
    }
  }

  depends_on = [aws_iam_role_policy.codebuild, aws_s3_object.source]
}
