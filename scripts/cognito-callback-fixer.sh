#!/usr/bin/env bash
# Post-create callback fix for the Cognito gateway app client.
#
# The gateway's OIDC redirect URI is https://<gateway-endpoint>/oauth/callback,
# but the endpoint isn't known when the app client is created. This patches the
# client's callback URL once the gateway exists. Invoked by the root
# terraform_data.cognito_callback_fixer.
#
# cognito-idp update-user-pool-client REPLACES the client config, so every
# setting the Terraform resource declares is re-specified here (the client
# secret is preserved by Cognito across updates). Keep this in sync with
# modules/idp-cognito/main.tf's aws_cognito_user_pool_client.gateway.
#
# Env: AWS_REGION, USER_POOL_ID, CLIENT_ID, CALLBACK_URL, SUPPORTED_IDPS
# (space-separated). Requires the AWS CLI.
set -euo pipefail

: "${AWS_REGION:?}"
: "${USER_POOL_ID:?}"
: "${CLIENT_ID:?}"
: "${CALLBACK_URL:?}"
: "${SUPPORTED_IDPS:?}"

echo "[cognito-callback-fixer] Setting callback ${CALLBACK_URL} on client ${CLIENT_ID}"

# shellcheck disable=SC2086 # SUPPORTED_IDPS is an intentional space-separated list
aws cognito-idp update-user-pool-client \
  --region "${AWS_REGION}" \
  --user-pool-id "${USER_POOL_ID}" \
  --client-id "${CLIENT_ID}" \
  --callback-urls "${CALLBACK_URL}" \
  --allowed-o-auth-flows code \
  --allowed-o-auth-scopes openid profile email \
  --allowed-o-auth-flows-user-pool-client \
  --supported-identity-providers ${SUPPORTED_IDPS} \
  --explicit-auth-flows ALLOW_REFRESH_TOKEN_AUTH \
  --prevent-user-existence-errors ENABLED \
  --read-attributes email custom:groups \
  --enable-token-revocation \
  >/dev/null

echo "[cognito-callback-fixer] Done."
