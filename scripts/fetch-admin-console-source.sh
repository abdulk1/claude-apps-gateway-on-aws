#!/usr/bin/env bash
# Vendors the admin console application source (FastAPI app + templates) from
# the upstream aws-samples reference repo into app/admin-console/.
#
# The gateway container context (app/gateway) is checked into this repo because
# it is small and central. The admin console is a full FastAPI application
# (~15 files) that belongs to the upstream sample; rather than fork it, we
# fetch the proven source on demand. Re-run after upstream updates.
#
# Usage: scripts/fetch-admin-console-source.sh
set -euo pipefail

REPO="aws-samples/sample-claude-apps-gateway-on-aws"
BRANCH="${BRANCH:-main}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/app/admin-console"

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: the GitHub CLI (gh) is required. Install it or download the" >&2
  echo "       admin-console/ directory from https://github.com/${REPO} manually." >&2
  exit 1
fi

echo "Fetching admin console source from ${REPO}@${BRANCH} into ${DEST}..."
mkdir -p "${DEST}"

# Walk the admin-console/ subtree and download each blob, preserving paths.
gh api "repos/${REPO}/git/trees/${BRANCH}?recursive=1" \
  --jq '.tree[] | select(.type=="blob") | select(.path | startswith("admin-console/")) | .path' \
| while read -r path; do
    rel="${path#admin-console/}"
    out="${DEST}/${rel}"
    mkdir -p "$(dirname "${out}")"
    echo "  ${rel}"
    gh api "repos/${REPO}/contents/${path}?ref=${BRANCH}" \
      --jq '.content' | base64 --decode > "${out}"
  done

echo "Done. app/admin-console is populated. Set enable_admin_console = true and apply."
