#!/bin/bash
set -e

echo "=== Retrieving cluster credentials ==="

CREDENTIALS_OUTPUT=$(crc console --credentials -o json 2>/dev/null || crc console --credentials 2>/dev/null || true)
if echo "$CREDENTIALS_OUTPUT" | jq -e '.clusterConfig' >/dev/null 2>&1; then
  KUBEADMIN_PASSWORD=$(echo "$CREDENTIALS_OUTPUT" | jq -r '.clusterConfig.adminCredentials.password')
else
  KUBEADMIN_PASSWORD=$(echo "$CREDENTIALS_OUTPUT" | grep 'password is' | awk '{print $NF}' | tr -d "'" | head -1)
fi
echo "::add-mask::$KUBEADMIN_PASSWORD"

API_URL="https://api.crc.testing:6443"
CONSOLE_URL="https://console-openshift-console.apps-crc.testing"

KUBECONFIG_PATH="$HOME/.crc/machines/crc/kubeconfig"

{
  echo "api-url=$API_URL"
  echo "console-url=$CONSOLE_URL"
  echo "kubeadmin-password=$KUBEADMIN_PASSWORD"
  echo "kubeconfig-path=$KUBECONFIG_PATH"
} >>"${GITHUB_OUTPUT}"
