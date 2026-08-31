#!/bin/bash
set -e

gha_error() {
  echo "::error::$1" >&2
  echo "[ERROR] $1" >&2
}

echo "=== Retrieving cluster credentials ==="

CREDENTIALS_OUTPUT=$(crc console --credentials -o json 2>/dev/null || crc console --credentials 2>/dev/null || true)
if echo "$CREDENTIALS_OUTPUT" | jq -e '.clusterConfig.adminCredentials.password | length > 0' >/dev/null 2>&1; then
  KUBEADMIN_PASSWORD=$(echo "$CREDENTIALS_OUTPUT" | jq -r '.clusterConfig.adminCredentials.password')
elif echo "$CREDENTIALS_OUTPUT" | grep -q 'kubeadmin -p'; then
  KUBEADMIN_PASSWORD=$(echo "$CREDENTIALS_OUTPUT" | sed -n "s/.*-u kubeadmin -p \([^ ]*\).*/\1/p" | head -1)
elif [ -s "$HOME/.crc/machines/crc/kubeadmin-password" ]; then
  KUBEADMIN_PASSWORD=$(cat "$HOME/.crc/machines/crc/kubeadmin-password")
else
  KUBEADMIN_PASSWORD=""
fi

if [ -z "$KUBEADMIN_PASSWORD" ] || [ "$KUBEADMIN_PASSWORD" = "null" ]; then
  gha_error "Failed to extract kubeadmin password from CRC credentials. Ensure the cluster is running and 'crc console --credentials' returns a valid password."
  exit 1
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
