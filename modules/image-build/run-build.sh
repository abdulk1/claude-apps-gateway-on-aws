#!/usr/bin/env bash
# Starts the image-build CodeBuild project and waits for it to finish.
# Invoked by the terraform_data.build local-exec provisioner.
#
# Env: PROJECT_NAME, AWS_REGION. Requires the AWS CLI and jq.
set -euo pipefail

: "${PROJECT_NAME:?PROJECT_NAME is required}"
: "${AWS_REGION:?AWS_REGION is required}"

echo "[image-build] Starting CodeBuild project ${PROJECT_NAME}..."
BUILD_ID="$(aws codebuild start-build \
  --project-name "${PROJECT_NAME}" \
  --region "${AWS_REGION}" \
  --query 'build.id' --output text)"
echo "[image-build] Build id: ${BUILD_ID}"

while true; do
  STATUS="$(aws codebuild batch-get-builds \
    --ids "${BUILD_ID}" \
    --region "${AWS_REGION}" \
    --query 'builds[0].buildStatus' --output text)"
  case "${STATUS}" in
    SUCCEEDED)
      echo "[image-build] Build SUCCEEDED."
      exit 0
      ;;
    IN_PROGRESS)
      echo "[image-build] Build in progress..."
      sleep 15
      ;;
    *)
      echo "[image-build] Build ended with status: ${STATUS}" >&2
      echo "[image-build] See CloudWatch Logs group /aws/codebuild/${PROJECT_NAME} for details." >&2
      exit 1
      ;;
  esac
done
