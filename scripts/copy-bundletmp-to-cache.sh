#!/bin/bash
set -e

mkdir -p "$HOME/.crc/cache"
if [ -d "$HOME/.crc/bundletmp" ] && [ "$(ls -A "$HOME/.crc/bundletmp" 2>/dev/null)" ]; then
  cp -r "$HOME/.crc/bundletmp"/* "$HOME/.crc/cache/"
else
  echo "No files found in bundletmp to copy or directory does not exist"
fi
