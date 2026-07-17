#!/bin/bash
set -e

CRC_VERSION="$1"

# Detect architecture
case "$(uname -m)" in
  x86_64) CRC_ARCH="amd64" ;;
  aarch64 | arm64) CRC_ARCH="arm64" ;;
  *)
    echo "Unsupported architecture: $(uname -m)"
    exit 1
    ;;
esac
echo "Detected architecture: $CRC_ARCH"

# Retry logic for downloading CRC
MAX_RETRIES=3
RETRY_COUNT=0
DOWNLOAD_SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES: Downloading CRC version $CRC_VERSION..."

  # Remove any partial download from previous attempt
  rm -f crc.tar.xz

  MIRROR_BASE="https://mirror.openshift.com/pub/openshift-v4/clients/crc/$CRC_VERSION"
  CRC_FILENAME="crc-linux-$CRC_ARCH.tar.xz"

  if curl -L -o crc.tar.xz "$MIRROR_BASE/$CRC_FILENAME"; then
    FILE_SIZE=$(stat -c%s crc.tar.xz 2>/dev/null || stat -f%z crc.tar.xz 2>/dev/null || echo 0)
    if [ "$FILE_SIZE" -le 1048576 ]; then
      echo "Download failed: File too small ($FILE_SIZE bytes), likely an error page"
    elif curl -sL -o sha256sum.txt "$MIRROR_BASE/sha256sum.txt"; then
      EXPECTED=$(grep "$CRC_FILENAME" sha256sum.txt | awk '{print $1}')
      if [ -z "$EXPECTED" ]; then
        echo "WARNING: No checksum found for $CRC_FILENAME in sha256sum.txt, skipping verification"
        DOWNLOAD_SUCCESS=true
        break
      fi
      ACTUAL=$(sha256sum crc.tar.xz | awk '{print $1}')
      if [ "$EXPECTED" = "$ACTUAL" ]; then
        echo "Download successful. File size: $FILE_SIZE bytes, SHA256 verified"
        DOWNLOAD_SUCCESS=true
        break
      else
        echo "SHA256 mismatch: expected $EXPECTED, got $ACTUAL"
      fi
    else
      echo "WARNING: Could not download sha256sum.txt, skipping verification"
      DOWNLOAD_SUCCESS=true
      break
    fi
  else
    echo "Download failed with curl error"
  fi

  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "Waiting 10 seconds before retry..."
    sleep 10
  fi
done

if [ "$DOWNLOAD_SUCCESS" = false ]; then
  echo "Failed to download CRC after $MAX_RETRIES attempts"
  exit 1
fi

tar -xf crc.tar.xz
CRC_DIR=$(find . -maxdepth 1 -type d -name 'crc-linux-*' | head -1)
if [ -n "$CRC_DIR" ] && [ -f "$CRC_DIR/crc" ]; then
  sudo mv "$CRC_DIR/crc" /usr/local/bin
else
  echo "Error: CRC binary not found in extracted archive"
  exit 1
fi
# Clean up immediately after extraction
rm -rf crc.tar.xz crc-linux-* sha256sum.txt
echo "=== Disk usage after CRC download ==="
df -h
