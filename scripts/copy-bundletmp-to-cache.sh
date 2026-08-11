#!/bin/bash
set -e

mkdir -p "$HOME/.crc/cache"
if [ -d "$HOME/.crc/bundletmp" ] && [ "$(ls -A "$HOME/.crc/bundletmp" 2>/dev/null)" ]; then
  cp -r "$HOME/.crc/bundletmp"/* "$HOME/.crc/cache/"

  min_size=$((1024 * 1024 * 1024))
  bundle_ok=true
  found_bundle=false
  for bundle in "$HOME/.crc/cache"/*.crcbundle; do
    [ -e "$bundle" ] || continue
    found_bundle=true
    file_size=$(stat --format='%s' "$bundle" 2>/dev/null || stat -f '%z' "$bundle" 2>/dev/null || echo 0)
    if [ "$file_size" -lt "$min_size" ]; then
      echo "WARNING: Bundle $(basename "$bundle") is only $((file_size / 1024 / 1024))MB, expected at least 1024MB. Removing."
      rm -f "$bundle"
      bundle_ok=false
    fi
  done
  if [ "$found_bundle" = false ]; then
    echo "WARNING: No .crcbundle files found in cache after copy. Fresh download will be triggered."
  elif [ "$bundle_ok" = false ]; then
    echo "WARNING: Corrupt bundle(s) removed. Fresh download will be triggered."
  else
    echo "Bundle cache integrity verified."
  fi
else
  echo "No files found in bundletmp to copy or directory does not exist"
fi
