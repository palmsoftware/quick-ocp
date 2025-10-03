#!/bin/bash
set -e

# Wait for cluster to be ready and accessible
echo "Waiting for cluster to be accessible..."
while ! oc get nodes --request-timeout='30s' &>/dev/null; do
  echo "Cluster not yet accessible, waiting..."
  sleep 10
done

# Wait for the node to be in Ready state
while [[ $(oc get nodes --request-timeout='30s' -o json | jq -r '.items[] | select(.metadata.name=="api.crc.testing") | .status.conditions[] | select(.reason=="KubeletReady") | .status') == "False" ]]; do
  echo "Waiting for node to be in Ready state"
  sleep 5
done
