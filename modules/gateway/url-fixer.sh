#!/usr/bin/env bash
# Post-create URL fix for the Claude gateway ECS Express Mode service.
# Re-applies the primary container with the real public URL substituted.
# Invoked by terraform_data.url_fixer.
#
# Env: AWS_REGION, SERVICE_ARN, PRIMARY_CONTAINER_JSON. Requires the AWS CLI.
#
# NOTE: ECS Express Mode is a brand-new API. If your installed AWS CLI names
# the update operation or its flags differently, adjust the invocation below
# to match `aws ecs update-express-gateway-service help`. The intent is
# unambiguous: set the primary container's GATEWAY_PUBLIC_URL to the service's
# own endpoint.
set -euo pipefail

: "${AWS_REGION:?}"
: "${SERVICE_ARN:?}"
: "${PRIMARY_CONTAINER_JSON:?}"

echo "[url-fixer] Patching GATEWAY_PUBLIC_URL on ${SERVICE_ARN}"

aws ecs update-express-gateway-service \
  --region "${AWS_REGION}" \
  --service-arn "${SERVICE_ARN}" \
  --primary-container "${PRIMARY_CONTAINER_JSON}"

echo "[url-fixer] Done. The service will roll to a new task with the real public URL."
