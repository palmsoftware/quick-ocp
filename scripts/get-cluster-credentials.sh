#!/bin/bash
set -e

echo "=== Retrieving cluster credentials ==="

KUBEADMIN_PASSWORD=$(crc console --credentials | grep 'password is' | awk '{print $NF}' | tr -d "'" | head -1)
echo "::add-mask::$KUBEADMIN_PASSWORD"

API_URL="https://api.crc.testing:6443"
CONSOLE_URL="https://console-openshift-console.apps-crc.testing"

echo "api-url=$API_URL" | tee -a "${GITHUB_OUTPUT}"
echo "console-url=$CONSOLE_URL" | tee -a "${GITHUB_OUTPUT}"
echo "kubeadmin-password=$KUBEADMIN_PASSWORD" | tee -a "${GITHUB_OUTPUT}"
