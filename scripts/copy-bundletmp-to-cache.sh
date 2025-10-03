#!/bin/bash
set -e

mkdir -p /home/runner/.crc/cache
if [ -d "/home/runner/.crc/bundletmp" ] && [ "$(ls -A /home/runner/.crc/bundletmp 2>/dev/null)" ]; then
  cp -r /home/runner/.crc/bundletmp/* /home/runner/.crc/cache/
else
  echo "No files found in bundletmp to copy or directory does not exist"
fi
