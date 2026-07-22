terraform {
  required_providers {
    aws    = { source = "hashicorp/aws" }
    random = { source = "hashicorp/random" }
  }
}

# Every generated secret the gateway and admin console need, plus the OIDC
# client secret (the one secret here that is external input, not generated).
# == ClaudeGatewaySecretsStack.
#
# Names use name_prefix but the gateway/console reference secrets by ARN
# (never by name), so there is no need for predictable names -- and a
# name_prefix keeps a redeploy from colliding with a same-named leftover.
# ~44 chars, no punctuation ~= `openssl rand -base64 32`, matching the sample.

resource "random_password" "jwt" {
  length  = 44
  special = false
}

resource "random_password" "admin_write_key" {
  length  = 44
  special = false
}

resource "random_password" "console_session" {
  length  = 44
  special = false
}

# JWT signing secret for gateway sessions.
resource "aws_secretsmanager_secret" "jwt" {
  name_prefix = "${var.name_prefix}-jwt-"
  description = "JWT signing secret for Claude apps gateway sessions"
}
resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = random_password.jwt.result
}

# OIDC client secret -- external input, required at boot (the gateway
# crash-loops without a real value, so it can never be a fill-in-later
# placeholder).
resource "aws_secretsmanager_secret" "oidc_client" {
  name_prefix = "${var.name_prefix}-oidc-client-"
  description = "OIDC client secret for the Claude apps gateway -- see docs/01-prerequisites.md."
}
resource "aws_secretsmanager_secret_version" "oidc_client" {
  secret_id     = aws_secretsmanager_secret.oidc_client.id
  secret_string = var.oidc_client_secret
}

# Admin API write key -- out-of-band CLI/automation verification only. The
# admin console never uses this; it authenticates as the signed-in admin.
resource "aws_secretsmanager_secret" "admin_write_key" {
  name_prefix = "${var.name_prefix}-admin-write-key-"
  description = "Admin API write key for the spend-limits API (CLI/automation verification only)"
}
resource "aws_secretsmanager_secret_version" "admin_write_key" {
  secret_id     = aws_secretsmanager_secret.admin_write_key.id
  secret_string = random_password.admin_write_key.result
}

# Session signing key for the admin console.
resource "aws_secretsmanager_secret" "console_session" {
  name_prefix = "${var.name_prefix}-console-session-"
  description = "Session signing key for the Claude gateway admin console"
}
resource "aws_secretsmanager_secret_version" "console_session" {
  secret_id     = aws_secretsmanager_secret.console_session.id
  secret_string = random_password.console_session.result
}
