# Remote state backend.
#
# This repo composes the Aurora master password in Terraform (see
# modules/database) and generates the VPN client private key in Terraform
# (see modules/vpn), so the state file WILL contain sensitive values. Use an
# encrypted remote backend with locking and least-privilege access -- do not
# leave state on a laptop or in a shared, unencrypted bucket.
#
# Uncomment and fill in for an S3 backend with native S3 state locking
# (use_lockfile, GA in the AWS provider -- no DynamoDB table required):
#
# terraform {
#   backend "s3" {
#     bucket       = "my-tf-state-bucket"
#     key          = "claude-apps-gateway/terraform.tfstate"
#     region       = "us-east-1"
#     encrypt      = true
#     use_lockfile = true
#   }
# }
#
# Until a backend is configured, Terraform uses local state
# (terraform.tfstate in this directory), which is .gitignored.
