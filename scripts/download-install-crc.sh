#!/bin/bash
set -e

CRC_VERSION="$1"

curl -L -o crc.tar.xz "https://mirror.openshift.com/pub/openshift-v4/clients/crc/$CRC_VERSION/crc-linux-amd64.tar.xz"
tar -xvf crc.tar.xz
if [ -d crc-linux-* ] && [ -f crc-linux-*/crc ]; then
  sudo mv crc-linux-*/crc /usr/local/bin
else
  echo "Error: CRC binary not found in extracted archive"
  exit 1
fi
# Clean up immediately after extraction
rm -rf crc.tar.xz crc-linux-*
echo "=== Disk usage after CRC download ==="
df -h
