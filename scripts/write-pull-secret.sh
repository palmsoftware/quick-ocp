#!/bin/bash
set -e

if [ -z "$PULL_SECRET" ]; then
  echo "[ERROR] PULL_SECRET environment variable is not set." >&2
  exit 1
fi

if ! echo "$PULL_SECRET" | jq empty 2>/dev/null; then
  echo "[ERROR] PULL_SECRET is not valid JSON. Verify the secret value in your repository settings." >&2
  exit 1
fi

if ! echo "$PULL_SECRET" | jq -e '.auths | length > 0' >/dev/null 2>&1; then
  echo "[ERROR] PULL_SECRET does not contain registry credentials (.auths is missing or empty)." >&2
  exit 1
fi

(umask 077 && echo "$PULL_SECRET" >pull-secret.json)
