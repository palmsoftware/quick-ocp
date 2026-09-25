#!/bin/bash
set -e

timeout="${WAIT_FOR_NODE_READY_TIMEOUT:-900}" # 15 minutes in seconds
elapsed=0
interval=10

# Debug: show CRC status and connectivity
echo "=== CRC status ==="
crc status 2>&1 || true
echo "=== DNS check ==="
getent hosts api.crc.testing 2>&1 || echo "api.crc.testing: not resolving"
echo "=== Connectivity check ==="
curl -sk --connect-timeout 5 https://api.crc.testing:6443 2>&1 | head -3 || true

# Wait for cluster to be ready and accessible
echo "Waiting for cluster to be accessible..."
while ! oc get nodes --request-timeout='30s' &>/dev/null; do
  echo "Cluster not yet accessible, waiting... (${elapsed}s/${timeout}s)"
  sleep $interval
  elapsed=$((elapsed + interval))
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "Timeout reached: Cluster not accessible after ${timeout}s"
    echo ""
    echo "=== CRC Status ==="
    crc status 2>&1 || true
    echo ""
    echo "=== Memory Usage ==="
    free -h 2>&1 || true
    echo ""
    echo "=== libvirt VM Status ==="
    sudo virsh list --all 2>/dev/null || true
    echo ""
    echo "=== CRC Daemon Logs (last 30 lines) ==="
    sudo journalctl -u "crc*" --no-pager -n 30 2>/dev/null || true
    exit 1
  fi
done

# Require every returned CRC node to report Ready=True.
get_node_readiness() {
  local nodes_json node_rows node_name readiness
  local saw_false=false saw_unknown=false node_count=0

  if ! nodes_json=$(oc get nodes --request-timeout='30s' -o json); then
    echo "Unable to query node readiness: oc get nodes failed; treating the node as not ready." >&2
    node_readiness="unknown"
    observed_nodes="unavailable"
    return 0
  fi

  if ! node_rows=$(jq -r '.items[] | [(.metadata.name // "<unknown>"), ([.status.conditions[]? | select(.type == "Ready") | .status] | if length == 1 then .[0] // "unknown" else "unknown" end)] | @tsv' <<<"$nodes_json"); then
    echo "Unable to query node readiness: jq could not parse the node data; treating the node as not ready." >&2
    node_readiness="unknown"
    observed_nodes="unavailable"
    return 0
  fi

  node_readiness="True"
  observed_nodes=""
  while IFS=$'\t' read -r node_name readiness; do
    [[ -n "$node_name" ]] || continue
    node_count=$((node_count + 1))
    if [[ -n "$observed_nodes" ]]; then
      observed_nodes+=", "
    fi
    observed_nodes+="${node_name} (Ready=${readiness})"

    case "$readiness" in
      True)
        ;;
      False)
        saw_false=true
        ;;
      *)
        saw_unknown=true
        ;;
    esac
  done <<<"$node_rows"

  if [[ "$node_count" -eq 0 ]]; then
    node_readiness="unknown"
    observed_nodes="none"
    echo "No nodes returned by oc get nodes; treating the node as not ready." >&2
  elif [[ "$saw_false" == true ]]; then
    node_readiness="False"
  elif [[ "$saw_unknown" == true ]]; then
    node_readiness="unknown"
  fi
}

# Wait for the node to be in Ready state
elapsed=0
while true; do
  get_node_readiness
  if [[ "$node_readiness" == "True" ]]; then
    break
  fi

  if [[ "$node_readiness" == "False" ]]; then
    echo "Waiting for node to be in Ready state (Ready=False; nodes: ${observed_nodes})... (${elapsed}s/${timeout}s)"
  else
    echo "Waiting for node to be in Ready state (Ready status unknown; nodes: ${observed_nodes})... (${elapsed}s/${timeout}s)"
  fi

  sleep 5
  elapsed=$((elapsed + 5))
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "Timeout reached: Node not ready after ${timeout}s (last Ready status: ${node_readiness}; observed nodes: ${observed_nodes})"
    exit 1
  fi
done
