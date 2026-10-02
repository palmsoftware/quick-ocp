#!/bin/bash
set -euo pipefail

STATE_BASE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"

gha_error() {
  echo "::error::$1" >&2
  echo "[ERROR] $1" >&2
}

if [[ -z "${PULL_SECRET:-}" ]]; then
  gha_error "PULL_SECRET environment variable is not set."
  echo "  Hint: Set the ocpPullSecret input using \${{ secrets.OCP_PULL_SECRET }} in your workflow." >&2
  echo "  If the secret is not created, add it at: Settings > Secrets and variables > Actions." >&2
  echo "  Pull secrets can be obtained from https://console.redhat.com/openshift/create/local." >&2
  exit 1
fi

if ! printf '%s' "$PULL_SECRET" | jq empty 2>/dev/null; then
  gha_error "PULL_SECRET is not valid JSON. Verify the secret value in your repository settings."
  exit 1
fi

if ! printf '%s' "$PULL_SECRET" | jq -e '.auths | length > 0' >/dev/null 2>&1; then
  gha_error "PULL_SECRET does not contain registry credentials (.auths is missing or empty)."
  exit 1
fi

if [[ -z "${GITHUB_ENV:-}" || -z "${GITHUB_OUTPUT:-}" ]]; then
  gha_error "GITHUB_ENV and GITHUB_OUTPUT are required to register pull secret cleanup."
  exit 1
fi

umask 077
STATE_DIR=$(mktemp -d "$STATE_BASE/quick-ocp-pull-secret.XXXXXX")
chmod 700 "$STATE_DIR"
STATE_REGISTERED=false

cleanup_unregistered_state() {
  if [[ "$STATE_REGISTERED" != true ]]; then
    rm -rf "$STATE_DIR"
  fi
}
trap cleanup_unregistered_state EXIT

printf 'QUICK_OCP_PULL_SECRET_STATE_DIR=%s\n' "$STATE_DIR" >>"$GITHUB_ENV"
STATE_REGISTERED=true

PULL_SECRET_FILE="$STATE_DIR/pull-secret.json"
printf '%s' "$PULL_SECRET" >"$PULL_SECRET_FILE"
printf 'path=%s\n' "$PULL_SECRET_FILE" >>"$GITHUB_OUTPUT"
