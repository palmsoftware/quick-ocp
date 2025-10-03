#!/bin/bash
set -e

echo "=== Moving CRC bundles for caching ==="
mkdir -p /home/runner/.crc/bundletmp
if [ -n "$(ls /home/runner/.crc/cache/*.crcbundle 2>/dev/null)" ]; then
  mv /home/runner/.crc/cache/*.crcbundle /home/runner/.crc/bundletmp/
  echo "Moved $(ls /home/runner/.crc/bundletmp/*.crcbundle | wc -l) bundle files"
else
  echo "No .crcbundle files found to move"
fi

echo "=== Disk usage after bundle move ==="
df -h
