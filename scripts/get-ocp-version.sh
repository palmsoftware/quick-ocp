#!/bin/bash
set -e

CRC_OUTPUT=$(crc version)
echo "$CRC_OUTPUT"
OCP_VERSION=$(echo "$CRC_OUTPUT" | grep OpenShift | awk '{ print $3 }')
echo "ocp_version=$OCP_VERSION" | tee "${GITHUB_OUTPUT}"
