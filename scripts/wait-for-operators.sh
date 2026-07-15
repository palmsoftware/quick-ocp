#!/bin/bash
set -e

timeout="${1:-600}"
[[ "$timeout" =~ ^[0-9]+$ ]] || {
  echo "ERROR: invalid timeout value: $timeout" >&2
  exit 1
}
elapsed=0
interval=10

while true; do
  if oc get co --no-headers | awk '{if ($3 != "True" || $4 != "False" || $5 != "False") exit 1}'; then
    echo "All operators are available, not progressing, and not degraded"
    break
  else
    echo "Waiting for operators to become available..."
    sleep $interval
    elapsed=$((elapsed + interval))
    if [ $elapsed -ge $timeout ]; then
      echo "Timeout reached: Not all operators are available"
      exit 1
    fi
  fi
done
