#!/bin/bash
set -e

echo "=== Setting up CRC cache on larger disk partition ==="
# Create CRC cache directory on /mnt (larger disk)
sudo mkdir -p /mnt/crc-cache
sudo chown -R runner:runner /mnt/crc-cache

# Create symlink from default CRC cache location to /mnt
mkdir -p /home/runner/.crc
if [ ! -L "/home/runner/.crc/cache" ]; then
  # If cache directory exists, move it first
  if [ -d "/home/runner/.crc/cache" ]; then
    mv /home/runner/.crc/cache/* /mnt/crc-cache/ 2>/dev/null || true
    rm -rf /home/runner/.crc/cache
  fi
  ln -sf /mnt/crc-cache /home/runner/.crc/cache
fi

# Also setup the machines directory on larger disk
sudo mkdir -p /mnt/crc-machines
sudo chown -R runner:runner /mnt/crc-machines
if [ ! -L "/home/runner/.crc/machines" ]; then
  if [ -d "/home/runner/.crc/machines" ]; then
    mv /home/runner/.crc/machines/* /mnt/crc-machines/ 2>/dev/null || true
    rm -rf /home/runner/.crc/machines
  fi
  ln -sf /mnt/crc-machines /home/runner/.crc/machines
fi

echo "=== CRC directories moved to larger disk ==="
ls -la /home/runner/.crc/
df -h
