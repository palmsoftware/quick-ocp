#!/bin/bash
set -e

# Right after crc start the API server can briefly reset connections while
# operators roll out (seen as "read: connection reset by peer"), so each
# policy change is retried. Both commands are idempotent.
attempts="${SET_ADM_POLICY_ATTEMPTS:-6}"
interval="${SET_ADM_POLICY_INTERVAL:-10}"

run_with_retry() {
  local attempt output
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if output=$("$@" --request-timeout=30s 2>&1); then
      echo "$output"
      return 0
    fi
    if ((attempt < attempts)); then
      echo "::warning::'$*' failed (attempt ${attempt}/${attempts}), retrying in ${interval}s: ${output}"
      sleep "$interval"
    fi
  done
  echo "ERROR: '$*' failed after ${attempts} attempts: ${output}" >&2
  return 1
}

run_with_retry oc adm policy add-scc-to-user privileged user
run_with_retry oc adm policy add-scc-to-group privileged system:authenticated
