#!/bin/bash
set -e

OCP_VERSION="$1"
ACTION_PATH="$2"

echo "=== Installing OpenShift CLI tools ==="
echo "Disk usage before tool installation:"
df -h

sudo "$ACTION_PATH/scripts/install-oc-tools.sh" --latest "$OCP_VERSION"

echo "=== Cleaning up after tool installation ==="
# Clean up any downloaded archives
sudo rm -rf /tmp/openshift-* /tmp/oc-* /tmp/kubectl-* 2>/dev/null || true

echo "Disk usage after tool installation and cleanup:"
df -h
