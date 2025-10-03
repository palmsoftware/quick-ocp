#!/bin/bash
set -e

echo "=== Ensuring swap exists on /mnt ==="
SWAPFILE="/mnt/swapfile"
# Create a ~8G swapfile if no swap is active
if ! sudo swapon --show | grep -q "."; then
  echo "No active swap detected; creating ${SWAPFILE}"
  sudo fallocate -l 8G "$SWAPFILE" || sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count=8192
  sudo chmod 600 "$SWAPFILE"
  sudo mkswap "$SWAPFILE"
  sudo swapon "$SWAPFILE"
else
  echo "Swap already active; skipping creation"
fi
# Prefer swap usage slightly to avoid OOM on transient spikes
if [ -w /proc/sys/vm/swappiness ]; then
  echo 80 | sudo tee /proc/sys/vm/swappiness
fi
echo "=== Active swap devices ==="
sudo swapon --show || true
