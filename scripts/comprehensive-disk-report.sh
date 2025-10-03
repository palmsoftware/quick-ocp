#!/bin/bash
set -e

echo "=================================="
echo "  FINAL DISK SPACE ANALYSIS"
echo "=================================="

echo ""
echo "=== Overall Disk Usage ==="
df -h

echo ""
echo "=== Disk Usage by Mount Point ==="
df -h | awk 'NR==1{print $0" MOUNT"} NR>1{print $0" "$6}' | column -t

echo ""
echo "=== Top 20 Largest Directories ==="
echo "Analyzing disk usage by directory (this may take a moment)..."
sudo du -h --max-depth=2 / 2>/dev/null | grep -E '^[0-9.]+[GM]' | sort -hr | head -20 || true

echo ""
echo "=== CRC-Specific Disk Usage ==="
if [ -d "/home/runner/.crc" ]; then
  echo "CRC home directory:"
  du -sh /home/runner/.crc/ 2>/dev/null || echo "Could not analyze CRC home directory"
  echo "CRC symlinks:"
  ls -la /home/runner/.crc/ 2>/dev/null || echo "Could not list CRC directory"
fi

if [ -d "/mnt/crc-cache" ]; then
  echo "CRC cache on /mnt:"
  du -sh /mnt/crc-cache/ 2>/dev/null || echo "Could not analyze CRC cache"
fi

if [ -d "/mnt/crc-machines" ]; then
  echo "CRC machines on /mnt:"
  du -sh /mnt/crc-machines/ 2>/dev/null || echo "Could not analyze CRC machines"
fi

echo ""
echo "=== Docker Storage Usage ==="
if [ -d "/mnt/docker-storage" ]; then
  echo "Docker storage on /mnt:"
  du -sh /mnt/docker-storage/ 2>/dev/null || echo "Could not analyze Docker storage"
fi
if [ -d "/var/lib/docker" ]; then
  echo "Docker storage on root:"
  du -sh /var/lib/docker/ 2>/dev/null || echo "Could not analyze Docker root storage"
fi

echo ""
echo "=== Available Space Summary ==="
ROOT_AVAIL=$(df --output=avail -BG / | tail -1 | tr -d 'G ')
MNT_AVAIL=$(df --output=avail -BG /mnt 2>/dev/null | tail -1 | tr -d 'G ' || echo "0")

echo "Root partition (/) available space: ${ROOT_AVAIL}GB"
echo "Mount partition (/mnt) available space: ${MNT_AVAIL}GB"
echo "Total available space: $((ROOT_AVAIL + MNT_AVAIL))GB"

echo ""
echo "=== Space Warnings ==="
if [ "$ROOT_AVAIL" -lt 2 ]; then
  echo "⚠️  WARNING: Root partition has less than 2GB available!"
elif [ "$ROOT_AVAIL" -lt 5 ]; then
  echo "⚠️  CAUTION: Root partition has less than 5GB available"
else
  echo "✅ Root partition space looks good"
fi

if [ "$MNT_AVAIL" -lt 2 ]; then
  echo "⚠️  WARNING: Mount partition has less than 2GB available!"
elif [ "$MNT_AVAIL" -lt 10 ]; then
  echo "⚠️  CAUTION: Mount partition has less than 10GB available"
else
  echo "✅ Mount partition space looks good"
fi

echo ""
echo "=== Largest Files (top 10) ==="
find / -type f -size +100M 2>/dev/null | head -10 | xargs -I {} sh -c 'echo "$(du -h "{}" 2>/dev/null | cut -f1) {}"' 2>/dev/null || echo "Could not analyze large files"

echo ""
echo "=================================="
echo "  END OF DISK SPACE ANALYSIS"
echo "=================================="
