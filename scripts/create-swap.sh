#!/bin/bash
set -e

echo "=== Ensuring swap exists on /mnt ==="
SWAPFILE="/mnt/swapfile"
SWAP_SIZE_GB=8
SWAP_SIZE_MB=$((SWAP_SIZE_GB * 1024))
SWAP_SIZE_KB=$((SWAP_SIZE_MB * 1024))
if ! sudo swapon --show | grep -q "."; then
  echo "No active swap detected; creating ${SWAP_SIZE_GB}G swapfile at ${SWAPFILE}"
  avail_kb=$(df --output=avail /mnt 2>/dev/null | tail -1 | tr -d ' ')
  if [ -z "$avail_kb" ] || [ "$avail_kb" -lt "$SWAP_SIZE_KB" ]; then
    avail_mb=$((${avail_kb:-0} / 1024))
    echo "WARNING: /mnt has only ${avail_mb}MB available, need ${SWAP_SIZE_MB}MB for swap. Skipping swap creation."
  else
    sudo fallocate -l "${SWAP_SIZE_GB}G" "$SWAPFILE" || sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count="$SWAP_SIZE_MB"
    sudo chmod 600 "$SWAPFILE"
    sudo mkswap "$SWAPFILE"
    sudo swapon "$SWAPFILE"
  fi
else
  echo "Swap already active; skipping creation"
fi
# Prefer swap usage slightly to avoid OOM on transient spikes
if [ -w /proc/sys/vm/swappiness ]; then
  echo 80 | sudo tee /proc/sys/vm/swappiness
fi
echo "=== Active swap devices ==="
sudo swapon --show || true
