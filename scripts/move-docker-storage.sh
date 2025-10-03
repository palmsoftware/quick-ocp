#!/bin/bash
set -e

echo "=== Before docker storage move ==="
df -h
lsblk

# Stop docker before moving storage
sudo systemctl stop docker || true

# Create mount point and move docker data
sudo mkdir -p /mnt/docker-storage

# If docker data exists, move it
if [ -d "/var/lib/docker" ] && [ "$(ls -A /var/lib/docker 2>/dev/null)" ]; then
  echo "Moving existing docker data to /mnt/docker-storage"
  sudo mv /var/lib/docker/* /mnt/docker-storage/ || true
fi

# Configure docker to use new location
sudo jq '.  +={"data-root" : "/mnt/docker-storage"}' </etc/docker/daemon.json >/tmp/docker-daemon.json
sudo cp /tmp/docker-daemon.json /etc/docker/daemon.json
cat /etc/docker/daemon.json

# Start docker
sudo systemctl start docker
sudo ls -la /mnt/docker-storage

echo "=== After docker storage move ==="
df -h
