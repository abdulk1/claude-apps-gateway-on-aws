# Remote state backend.
#
# This repo composes the Aurora master password in Terraform (see
# modules/database) and generates the VPN client private key in Terraform
# (see modules/vpn), so the state file WILL contain sensitive values. Use an
# encrypted remote backend with locking and least-privilege access -- do not
# leave state on a laptop or in a shared, unencrypted bucket.

terraform {
  backend "s3" {
    bucket       = "aws-sandbox-terraform"
    key          = "claude-apps-gateway/terraform.tfstate"
    region       = "us-east-2" # bucket's region (state lives here); resources deploy to var.aws_region (us-east-1)
    encrypt      = true
    use_lockfile = true
  }
}

