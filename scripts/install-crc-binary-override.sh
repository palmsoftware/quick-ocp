#!/bin/bash
set -e

BINARY_PATH="$1"

if [ -z "$BINARY_PATH" ] || [ ! -f "$BINARY_PATH" ]; then
  echo "Usage: install-crc-binary-override.sh <path-to-binary>"
  echo "Binary not found: $BINARY_PATH"
  exit 1
fi

echo "=== Installing CRC binary override ==="
echo "Source: $BINARY_PATH"

echo "--- Stock CRC version ---"
crc version 2>&1 || echo "(not installed yet)"

echo "--- Installing override binary ---"
sudo install -m 755 "$BINARY_PATH" /usr/local/bin/crc

echo "--- Override CRC version ---"
crc version

echo "--- Re-applying vsock capabilities ---"
sudo setcap cap_net_bind_service=+eip /usr/local/bin/crc 2>/dev/null || true

echo "=== CRC binary override complete ==="
