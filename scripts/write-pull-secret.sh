#!/bin/bash
set -e

if [ -z "$PULL_SECRET" ]; then
  echo "[ERROR] PULL_SECRET environment variable is not set." >&2
  echo "  Hint: Set the ocpPullSecret input using \${{ secrets.OCP_PULL_SECRET }} in your workflow." >&2
  echo "  If the secret is not created, add it at: Settings > Secrets and variables > Actions." >&2
  echo "  Pull secrets can be obtained from https://console.redhat.com/openshift/create/local." >&2
  exit 1
fi

(umask 077 && echo "$PULL_SECRET" >pull-secret.json)
