#!/bin/bash
set -e

if [ -z "$PULL_SECRET" ]; then
  echo "[ERROR] PULL_SECRET environment variable is not set." >&2
  exit 1
fi

(umask 077 && echo "$PULL_SECRET" >pull-secret.json)
