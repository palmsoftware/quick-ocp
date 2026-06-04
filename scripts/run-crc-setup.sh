#!/bin/bash
set -e

echo "=== Running CRC setup ==="
sudo -su $USER crc setup --log-level debug --show-progressbars

echo "=== Disk usage after CRC setup ==="
df -h

echo "=== Starting CRC ==="
max_attempts=3
attempt=1

while [ $attempt -le $max_attempts ]; do
  echo "=== CRC start attempt $attempt of $max_attempts ==="

  start_output=$(sudo -su $USER crc start --pull-secret-file pull-secret.json --log-level debug 2>&1) || true
  echo "$start_output"

  if echo "$start_output" | grep -q "Cannot update kubeconfig"; then
    echo "WARNING: kubeconfig update failed during CRC start"
    if [ $attempt -lt $max_attempts ]; then
      echo "Stopping CRC and retrying..."
      sudo -su $USER crc stop || true
      sleep 10
      attempt=$((attempt + 1))
      continue
    else
      echo "ERROR: All $max_attempts attempts failed with kubeconfig error"
      exit 1
    fi
  fi

  break
done

# Clean up pull secret immediately after use
rm -f pull-secret.json

echo "=== Disk usage after CRC start ==="
df -h
