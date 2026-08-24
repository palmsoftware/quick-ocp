#!/bin/bash
set -e

CRC_JSON=$(crc version -o json 2>/dev/null || true)

if echo "$CRC_JSON" | jq -e '.openshiftVersion' >/dev/null 2>&1; then
  OCP_VERSION=$(echo "$CRC_JSON" | jq -r '.openshiftVersion')
else
  CRC_OUTPUT=$(crc version)
  echo "$CRC_OUTPUT"
  OCP_VERSION=$(echo "$CRC_OUTPUT" | grep OpenShift | awk '{ print $3 }')
fi

echo "ocp_version=$OCP_VERSION" >>"${GITHUB_OUTPUT}"
echo "OpenShift version: $OCP_VERSION"
