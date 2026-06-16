#!/bin/bash
set -e

echo "=== Moving CRC bundles for caching ==="
mkdir -p "$HOME/.crc/bundletmp"
if [ -n "$(ls "$HOME/.crc/cache"/*.crcbundle 2>/dev/null)" ]; then
  mv "$HOME/.crc/cache"/*.crcbundle "$HOME/.crc/bundletmp/"
  echo "Moved $(ls "$HOME/.crc/bundletmp"/*.crcbundle | wc -l) bundle files"
else
  echo "No .crcbundle files found to move"
fi

echo "=== Disk usage after bundle move ==="
df -h
