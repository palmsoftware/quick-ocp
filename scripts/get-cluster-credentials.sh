#!/bin/bash
set -e

echo "=== Retrieving cluster credentials ==="

KUBEADMIN_PASSWORD=$(crc console --credentials | grep 'password is' | awk '{print $NF}' | tr -d "'" | head -1)
echo "::add-mask::$KUBEADMIN_PASSWORD"

API_URL="https://api.crc.testing:6443"
CONSOLE_URL="https://console-openshift-console.apps-crc.testing"

KUBECONFIG_PATH="$HOME/.crc/machines/crc/kubeconfig"

echo "api-url=$API_URL" >>"${GITHUB_OUTPUT}"
echo "console-url=$CONSOLE_URL" >>"${GITHUB_OUTPUT}"
echo "kubeadmin-password=$KUBEADMIN_PASSWORD" >>"${GITHUB_OUTPUT}"
echo "kubeconfig-path=$KUBECONFIG_PATH" >>"${GITHUB_OUTPUT}"
