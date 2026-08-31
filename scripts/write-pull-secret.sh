#!/bin/bash
set -e

gha_error() {
  echo "::error::$1" >&2
  echo "[ERROR] $1" >&2
}

if [ -z "$PULL_SECRET" ]; then
  gha_error "PULL_SECRET environment variable is not set."
  echo "  Hint: Set the ocpPullSecret input using \${{ secrets.OCP_PULL_SECRET }} in your workflow." >&2
  echo "  If the secret is not created, add it at: Settings > Secrets and variables > Actions." >&2
  echo "  Pull secrets can be obtained from https://console.redhat.com/openshift/create/local." >&2
  exit 1
fi

if ! echo "$PULL_SECRET" | jq empty 2>/dev/null; then
  gha_error "PULL_SECRET is not valid JSON. Verify the secret value in your repository settings."
  exit 1
fi

if ! echo "$PULL_SECRET" | jq -e '.auths | length > 0' >/dev/null 2>&1; then
  gha_error "PULL_SECRET does not contain registry credentials (.auths is missing or empty)."
  exit 1
fi

(umask 077 && echo "$PULL_SECRET" >pull-secret.json)
