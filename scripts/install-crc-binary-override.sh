#!/bin/bash
set -e

RELEASE_TAG="$1"
REPO="$2"

if [ -z "$RELEASE_TAG" ] || [ -z "$REPO" ]; then
  echo "Usage: install-crc-binary-override.sh <release-tag> <repo>"
  exit 1
fi

echo "=== Installing CRC binary override ==="
echo "Release: $RELEASE_TAG from $REPO"

echo "--- Backing up stock CRC binary ---"
sudo cp /usr/local/bin/crc /usr/local/bin/crc.stock
echo "Stock CRC version:"
/usr/local/bin/crc.stock version

echo "--- Downloading override binary ---"
gh release download "$RELEASE_TAG" --repo "$REPO" --pattern "crc-linux-amd64" --dir /tmp --clobber
sudo install -m 755 /tmp/crc-linux-amd64 /usr/local/bin/crc
rm -f /tmp/crc-linux-amd64

echo "--- Override CRC version ---"
crc version

echo "--- Re-applying vsock capabilities ---"
sudo setcap cap_net_bind_service=+eip /usr/local/bin/crc 2>/dev/null || true

echo "--- Running enhanced preflight check ---"
crc setup --check-only 2>&1 || true

echo "=== CRC binary override complete ==="
