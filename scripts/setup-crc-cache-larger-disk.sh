#!/bin/bash
set -e

echo "=== Setting up CRC cache on larger disk partition ==="
# Create CRC cache directory on /mnt (larger disk)
sudo mkdir -p /mnt/crc-cache
sudo chown -R "$USER:$USER" /mnt/crc-cache

# Create symlink from default CRC cache location to /mnt
mkdir -p "$HOME/.crc"
if [ ! -L "$HOME/.crc/cache" ]; then
  # If cache directory exists, move it first
  if [ -d "$HOME/.crc/cache" ]; then
    mv "$HOME/.crc/cache"/* /mnt/crc-cache/ 2>/dev/null || true
    rm -rf "$HOME/.crc/cache"
  fi
  ln -sf /mnt/crc-cache "$HOME/.crc/cache"
fi

# Also setup the machines directory on larger disk
sudo mkdir -p /mnt/crc-machines
sudo chown -R "$USER:$USER" /mnt/crc-machines
if [ ! -L "$HOME/.crc/machines" ]; then
  if [ -d "$HOME/.crc/machines" ]; then
    mv "$HOME/.crc/machines"/* /mnt/crc-machines/ 2>/dev/null || true
    rm -rf "$HOME/.crc/machines"
  fi
  ln -sf /mnt/crc-machines "$HOME/.crc/machines"
fi

echo "=== CRC directories moved to larger disk ==="
ls -la "$HOME/.crc/"
df -h
