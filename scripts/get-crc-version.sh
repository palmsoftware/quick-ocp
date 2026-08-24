#!/bin/bash
set -e

CRC_JSON=$(crc version -o json 2>/dev/null || true)

if echo "$CRC_JSON" | jq -e '.version' >/dev/null 2>&1; then
  VERSION_NUMBER=$(echo "$CRC_JSON" | jq -r '.version')
else
  CRC_OUTPUT=$(crc version)
  echo "$CRC_OUTPUT"
  VERSION_NUMBER=$(echo "$CRC_OUTPUT" | grep CRC | awk '{ print $3 }')
fi

echo "version_number=$VERSION_NUMBER" >>"${GITHUB_OUTPUT}"
echo "CRC version: $VERSION_NUMBER"
