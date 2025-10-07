#!/bin/bash
set -e

CRC_VERSION="$1"

# Retry logic for downloading CRC
MAX_RETRIES=3
RETRY_COUNT=0
DOWNLOAD_SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES: Downloading CRC version $CRC_VERSION..."

  # Remove any partial download from previous attempt
  rm -f crc.tar.xz

  if curl -L -o crc.tar.xz "https://mirror.openshift.com/pub/openshift-v4/clients/crc/$CRC_VERSION/crc-linux-amd64.tar.xz"; then
    # Verify the downloaded file is valid (should be larger than 1MB)
    FILE_SIZE=$(stat -c%s crc.tar.xz 2>/dev/null || stat -f%z crc.tar.xz 2>/dev/null || echo 0)
    if [ "$FILE_SIZE" -gt 1048576 ]; then
      echo "Download successful. File size: $FILE_SIZE bytes"
      DOWNLOAD_SUCCESS=true
      break
    else
      echo "Download failed: File too small ($FILE_SIZE bytes), likely an error page"
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
