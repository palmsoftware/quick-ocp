#!/bin/bash
set -e

echo "=== Cleaning up unnecessary files after CRC start ==="

# Remove bundle files to save space
rm -rf /home/runner/.crc/bundletmp

# Clean up any leftover archives and temp files
find /tmp -name "*.tar*" -o -name "*.zip" -o -name "*.gz" -exec rm -f {} \; 2>/dev/null || true
find /var/tmp -name "*.tar*" -o -name "*.zip" -o -name "*.gz" -exec rm -f {} \; 2>/dev/null || true

# Clean package manager cache again
sudo apt-get clean
sudo apt-get autoremove --purge -y

# Clean Docker again
docker system prune -f --volumes || true

echo "=== Disk usage after aggressive cleanup ==="
df -h
