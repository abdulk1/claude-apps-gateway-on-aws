terraform {
  required_providers {
    aws     = { source = "hashicorp/aws" }
    random  = { source = "hashicorp/random" }
    archive = { source = "hashicorp/archive" }
  }
}

# Cognito user pool acting as the OIDC "bridge" in front of IAM Identity
# Center. The Claude apps gateway is OIDC-only ("SAML, LDAP... Not supported.
# OIDC only. Front with an OIDC bridge if needed." -- code.claude.com docs), so
# Identity Center (which federates to third-party apps over SAML) sits BEHIND
# Cognito: Cognito speaks OIDC to the gateway and SAML to Identity Center.
#
# Two-phase setup (see docs/01-prerequisites.md):
#   1. Apply with identity_center_saml_metadata_url = null. This creates the
#      pool + hosted-UI domain, whose ACS URL and entity ID you enter when you
#      create the customer-managed SAML app in Identity Center.
#   2. Set identity_center_saml_metadata_url to that app's metadata URL and
#      apply again. This creates the SAML IdP and points the app client at it.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "random_id" "domain" {
  byte_length = 3
}

locals {
  domain_prefix      = coalesce(var.domain_prefix, "${var.name_prefix}-${random_id.domain.hex}")
  create_saml        = var.identity_center_saml_metadata_url != null && var.identity_center_saml_metadata_url != ""
  saml_provider_name = "IdentityCenter"

  hosted_domain = "${local.domain_prefix}.auth.${var.region}.amazoncognito.com"
  # What you enter into the Identity Center customer-managed SAML application:
  saml_acs_url   = "https://${local.hosted_domain}/saml2/idpresponse"
  saml_entity_id = "urn:amazon:cognito:sp:${aws_cognito_user_pool.this.id}"

  supported_idps = local.create_saml ? [aws_cognito_identity_provider.identity_center[0].provider_name] : ["COGNITO"]
}

########################################
# User pool + hosted-UI domain
########################################

resource "aws_cognito_user_pool" "this" {
  name = "${var.name_prefix}-users"

  # Federated (external) users are the norm here; keep auto-verification off
  # since Identity Center owns the identities.
  username_attributes = ["email"]

  # Custom attribute that the SAML groups attribute maps into; the pre-token
  # Lambda turns it into the gateway's `groups` claim.
  schema {
    name                     = "groups"
    attribute_data_type      = "String"
    mutable                  = true
    developer_only_attribute = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  lambda_config {
    pre_token_generation_config {
      lambda_arn     = aws_lambda_function.pre_token.arn
      lambda_version = "V2_0"
    }
  }

  # Cognito validates it can invoke the trigger at pool-create time, so the
  # invoke permission must exist first.
  depends_on = [aws_lambda_permission.cognito_invoke]
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = local.domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}

########################################
# SAML federation to IAM Identity Center (phase 2)
########################################

resource "aws_cognito_identity_provider" "identity_center" {
  count = local.create_saml ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.this.id
  provider_name = local.saml_provider_name
  provider_type = "SAML"

  provider_details = {
    MetadataURL = var.identity_center_saml_metadata_url
    IDPSignout  = "false"
  }

  # Map the Identity Center SAML assertion attributes onto Cognito attributes.
  # custom:groups carries group membership, which the pre-token Lambda promotes
  # to the `groups` claim the gateway matches admin_groups against.
  attribute_mapping = {
    email           = var.saml_email_attribute
    "custom:groups" = var.saml_groups_attribute
  }
}

########################################
# Confidential app client for the gateway
########################################

resource "aws_cognito_user_pool_client" "gateway" {
  name         = "${var.name_prefix}-gateway"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret                      = true # confidential client -> client_secret
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  # Cognito rejects unknown scopes: `groups` and `offline_access` are NOT valid
  # Cognito scopes. Groups arrive via the pre-token `groups` claim, and Cognito
  # issues refresh tokens for the code flow without offline_access.
  allowed_oauth_scopes         = ["openid", "profile", "email"]
  supported_identity_providers = local.supported_idps

  callback_urls                 = var.callback_urls
  explicit_auth_flows           = ["ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
  read_attributes               = ["email", "custom:groups"]

  lifecycle {
    # The real callback (https://<gateway-endpoint>/oauth/callback) is patched
    # in by the root cognito_callback_fixer once the gateway exists -- the
    # gateway endpoint isn't knowable when this client is created.
    ignore_changes = [callback_urls]
  }
}

########################################
# Pre-token generation Lambda: emit the `groups` claim
########################################

data "archive_file" "pre_token" {
  type        = "zip"
  source_file = "${path.module}/lambda/pre_token.py"
  output_path = "${path.module}/.build/pre_token.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "pre_token" {
  name_prefix        = "${var.name_prefix}-pretoken-"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "pre_token_logs" {
  role       = aws_iam_role.pre_token.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "pre_token" {
  function_name    = "${var.name_prefix}-pre-token"
  role             = aws_iam_role.pre_token.arn
  runtime          = var.lambda_runtime
  handler          = "pre_token.handler"
  filename         = data.archive_file.pre_token.output_path
  source_code_hash = data.archive_file.pre_token.output_base64sha256
  timeout          = 5
}

resource "aws_lambda_permission" "cognito_invoke" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pre_token.function_name
  principal     = "cognito-idp.amazonaws.com"
  # Scoped to this account rather than the pool ARN, so this permission doesn't
  # depend on the pool (the pool depends on this permission -- see above).
  source_account = data.aws_caller_identity.current.account_id
}
