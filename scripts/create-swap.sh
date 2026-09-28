#!/bin/bash
set -euo pipefail

echo "=== Ensuring swap exists on /mnt ==="
SWAP_DIR="${SWAP_DIR:-/mnt}"
SWAPFILE_BASE="${SWAPFILE_BASE:-${SWAP_DIR}/swapfile}"
PROC_SWAPS_FILE="${PROC_SWAPS_FILE:-/proc/swaps}"
SWAP_TARGET_GB=8
SWAPPINESS=100
SWAP_TARGET_KB=$((SWAP_TARGET_GB * 1024 * 1024))
CURRENT_SWAP_KB=$(awk 'NR > 1 { total += $3 } END { print total + 0 }' "$PROC_SWAPS_FILE")

if [ "$CURRENT_SWAP_KB" -lt "$SWAP_TARGET_KB" ]; then
  ADD_SWAP_KB=$((SWAP_TARGET_KB - CURRENT_SWAP_KB))
  ADD_SWAP_MB=$(((ADD_SWAP_KB + 1023) / 1024))
  echo "Active swap is $((CURRENT_SWAP_KB / 1024))MiB; adding ${ADD_SWAP_MB}MiB to reach ${SWAP_TARGET_GB}GiB"

  avail_kb=$(df --output=avail "$SWAP_DIR" 2>/dev/null | tail -1 | tr -d ' ')
  if [ -z "$avail_kb" ] || [ "$avail_kb" -lt "$ADD_SWAP_KB" ]; then
    avail_mb=$((${avail_kb:-0} / 1024))
    echo "WARNING: ${SWAP_DIR} has only ${avail_mb}MiB available, need ${ADD_SWAP_MB}MiB for swap. Skipping swap creation."
  else
    SWAPFILE="$SWAPFILE_BASE"
    suffix=1
    while [ -e "$SWAPFILE" ]; do
      SWAPFILE="${SWAPFILE_BASE}.${suffix}"
      suffix=$((suffix + 1))
    done

    sudo fallocate -l "${ADD_SWAP_MB}M" "$SWAPFILE" || {
      sudo rm -f "$SWAPFILE"
      sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count="$ADD_SWAP_MB"
    }
    sudo chmod 600 "$SWAPFILE"
    sudo mkswap "$SWAPFILE"
    sudo swapon "$SWAPFILE"
  fi
else
  echo "Active swap is $((CURRENT_SWAP_KB / 1024))MiB; target ${SWAP_TARGET_GB}GiB already met"
fi

if sudo sysctl -w "vm.swappiness=${SWAPPINESS}"; then
  echo "Applied vm.swappiness=${SWAPPINESS}"
else
  echo "::warning::Unable to set vm.swappiness=${SWAPPINESS}; keeping the runner default"
fi

echo "=== Active swap devices ==="
sudo swapon --show || true
