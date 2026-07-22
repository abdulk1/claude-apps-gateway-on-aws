#!/bin/sh
# Entrypoint wrapper for the Claude apps gateway container.
#
# Substitutes YAML flow-sequence placeholders in gateway.yaml with real values
# from the environment before the gateway binary reads the config file:
#   ${AVAILABLE_MODELS_RAW}  -- the model allow-list
#   ${OIDC_SCOPES_RAW}       -- the OIDC scopes list
# Both are lists, and the gateway's own ${VAR} expansion only fills scalar
# positions, not list positions -- doing the substitution at the shell level
# before the gateway reads the file bypasses that constraint. It also lets the
# model allow-list change via a plain ECS env update with no image rebuild.
#
# Each must be a YAML flow-sequence string, e.g.:
#   AVAILABLE_MODELS_RAW="[claude-sonnet-4-6, claude-opus-4-8]"
#   OIDC_SCOPES_RAW="[openid, profile, email]"

set -e

if [ -z "${AVAILABLE_MODELS_RAW:-}" ]; then
  echo "[entrypoint] ERROR: AVAILABLE_MODELS_RAW is not set. Cannot start gateway." >&2
  exit 1
fi

# Default the scopes list if unset, so the gateway never fails closed on a
# missing scopes value (Cognito's minimal set).
: "${OIDC_SCOPES_RAW:=[openid, profile, email]}"

# Write the substituted config to a writable temp path
# (the original /etc/claude/gateway.yaml is read-only in the image layer)
sed \
  -e "s|\${AVAILABLE_MODELS_RAW}|${AVAILABLE_MODELS_RAW}|g" \
  -e "s|\${OIDC_SCOPES_RAW}|${OIDC_SCOPES_RAW}|g" \
  /etc/claude/gateway.yaml > /tmp/gateway-resolved.yaml

exec claude gateway --config /tmp/gateway-resolved.yaml
