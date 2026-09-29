#!/usr/bin/env bash
set -euo pipefail

STATE_BASE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
STATE_DIR="${QUICK_OCP_PULL_SECRET_STATE_DIR:-}"

if [[ -z "$STATE_DIR" ]]; then
  echo "Pull secret state is not set, nothing to clean up"
  exit 0
fi

case "$STATE_DIR" in
  "$STATE_BASE"/quick-ocp-pull-secret.*) ;;
  *)
    echo "Refusing to clean an unexpected pull secret state path" >&2
    exit 1
    ;;
esac

if [[ ! -d "$STATE_DIR" || -L "$STATE_DIR" ]]; then
  echo "Pull secret state directory not found, nothing to clean up"
  exit 0
fi

rm -rf "$STATE_DIR"
echo "Temporary pull secret removed"
