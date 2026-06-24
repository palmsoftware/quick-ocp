#!/bin/bash
set -e

timeout=900 # 15 minutes in seconds
elapsed=0
interval=10

# Debug: show CRC status and connectivity
echo "=== CRC status ==="
sudo -su "$USER" crc status 2>&1 || true
echo "=== DNS check ==="
getent hosts api.crc.testing 2>&1 || echo "api.crc.testing: not resolving"
echo "=== Connectivity check ==="
curl -sk --connect-timeout 5 https://api.crc.testing:6443 2>&1 | head -3 || true

# Wait for cluster to be ready and accessible
echo "Waiting for cluster to be accessible..."
while ! oc get nodes --request-timeout='30s' &>/dev/null; do
  echo "Cluster not yet accessible, waiting..."
  sleep $interval
  elapsed=$((elapsed + interval))
  if [ $elapsed -ge $timeout ]; then
    echo "Timeout reached: Cluster not accessible after ${timeout}s"
    exit 1
  fi
done

# Wait for the node to be in Ready state
while [[ $(oc get nodes --request-timeout='30s' -o json | jq -r '.items[] | select(.metadata.name=="api.crc.testing") | .status.conditions[] | select(.reason=="KubeletReady") | .status') == "False" ]]; do
  echo "Waiting for node to be in Ready state"
  sleep 5
  elapsed=$((elapsed + 5))
  if [ $elapsed -ge $timeout ]; then
    echo "Timeout reached: Node not ready after ${timeout}s"
    exit 1
  fi
done
