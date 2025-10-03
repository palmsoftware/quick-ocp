#!/bin/bash
set -e

echo "=== Final disk usage statistics ==="
df -h
echo "=== Disk usage by directory (top 10) ==="
sudo du -h --max-depth=1 / 2>/dev/null | sort -hr | head -10 || true
echo "=== CRC-specific disk usage ==="
du -h /home/runner/.crc/ 2>/dev/null || echo "CRC directory not found"
du -h /mnt/crc-* 2>/dev/null || echo "CRC mnt directories not found"
echo "=== Available space check ==="
AVAILABLE_GB=$(df --output=avail -BG / | tail -1 | tr -d 'G ')
echo "Available space: ${AVAILABLE_GB}GB"
if [ "$AVAILABLE_GB" -lt 2 ]; then
  echo "WARNING: Less than 2GB available space remaining!"
fi
