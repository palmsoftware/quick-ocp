#!/bin/bash
set -e

timeout="${1:-600}"
[[ "$timeout" =~ ^[0-9]+$ ]] || {
  echo "ERROR: invalid timeout value: $timeout" >&2
  exit 1
}
elapsed=0
interval=10

excluded=$(oc get clusterversion/version -ojsonpath='{range .spec.overrides[?(@.kind=="ClusterOperator")]}{.name}{"\n"}{end}' 2>/dev/null || true)
if [ -n "$excluded" ]; then
  exclude_pattern=$(echo "$excluded" | paste -sd'|' -)
  echo "Excluding unmanaged operators from readiness check: $(echo "$excluded" | paste -sd', ' -)"
fi

while true; do
  # The API server can briefly reset connections while operators roll out
  # renewed certificates, so a failed query is retried until the timeout.
  if ! co_status=$(oc get co --no-headers --request-timeout='30s'); then
    not_ready="  Unable to query cluster operators: oc get co failed; retrying."
  else
    if [ -n "${exclude_pattern:-}" ]; then
      co_status=$(echo "$co_status" | grep -v -E "^($exclude_pattern) " || true)
    fi
    if [ -z "$co_status" ]; then
      not_ready="  No cluster operators returned by oc get co; retrying."
    else
      not_ready=$(echo "$co_status" | awk '$3 != "True" || $4 != "False" || $5 != "False" {print "  " $1, "Available="$3, "Progressing="$4, "Degraded="$5}')
    fi
  fi

  if [ -z "$not_ready" ]; then
    echo "All operators are available, not progressing, and not degraded"
    break
  else
    echo "Waiting for operators to become available... (${elapsed}s/${timeout}s)"
    echo "$not_ready"
    sleep "$interval"
    elapsed=$((elapsed + interval))
    if [ "$elapsed" -ge "$timeout" ]; then
      echo "Timeout reached: Not all operators are available after ${timeout}s"
      echo ""
      echo "=== Cluster Operator Status ==="
      oc get co 2>&1 || true
      exit 1
    fi
  fi
done
