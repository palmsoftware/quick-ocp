#!/bin/bash
set -e

timeout="${1:-600}"
[[ "$timeout" =~ ^[0-9]+$ ]] || {
  echo "ERROR: invalid timeout value: $timeout" >&2
  exit 1
}
elapsed=0
interval=10
not_ready_names=""

# On timeout, explain why each operator is stuck: its condition messages,
# the pods in its namespaces, unhealthy pods cluster-wide, node pressure,
# and recent warning events. Every query is best effort.
dump_operator_diagnostics() {
  local name ns namespaces
  for name in $not_ready_names; do
    echo ""
    echo "=== Conditions for clusteroperator/${name} ==="
    oc get co "$name" --request-timeout='30s' -o jsonpath='{range .status.conditions[*]}{.type}={.status}: {.message}{"\n"}{end}' 2>&1 || true

    namespaces=$(oc get co "$name" --request-timeout='30s' -o jsonpath='{range .status.relatedObjects[?(@.resource=="namespaces")]}{.name}{"\n"}{end}' 2>/dev/null || true)
    for ns in $namespaces; do
      echo ""
      echo "=== Pods in ${ns} (related to ${name}) ==="
      oc get pods -n "$ns" --request-timeout='30s' -o wide 2>&1 || true
    done
  done

  echo ""
  echo "=== Pods not Running or Succeeded (all namespaces) ==="
  oc get pods -A --request-timeout='30s' -o wide --field-selector=status.phase!=Running,status.phase!=Succeeded 2>&1 || true

  echo ""
  echo "=== Node conditions and allocated resources ==="
  oc describe nodes --request-timeout='30s' 2>&1 | sed -n -e '/^Conditions:/,/^Addresses:/p' -e '/^Allocated resources:/,/^Events:/p' || true

  echo ""
  echo "=== Recent warning events (last 30) ==="
  oc get events -A --request-timeout='30s' --field-selector=type=Warning --sort-by=.lastTimestamp 2>&1 | tail -30 || true

  echo ""
  echo "=== Host memory ==="
  free -m 2>&1 || true
}

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
      not_ready_names=$(echo "$co_status" | awk '$3 != "True" || $4 != "False" || $5 != "False" {print $1}')
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
      dump_operator_diagnostics
      exit 1
    fi
  fi
done
