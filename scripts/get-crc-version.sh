#!/bin/bash
set -e

CRC_OUTPUT=$(crc version)
echo "$CRC_OUTPUT"
VERSION_NUMBER=$(echo "$CRC_OUTPUT" | grep CRC | awk '{ print $3 }')
echo "version_number=$VERSION_NUMBER" | tee "${GITHUB_OUTPUT}"
