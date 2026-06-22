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

  start_exit_code=0
  start_output=$(sudo -su $USER crc start --pull-secret-file pull-secret.json --log-level debug 2>&1) || start_exit_code=$?
  echo "$start_output"

  if [ $start_exit_code -eq 0 ]; then
    break
  fi

  if echo "$start_output" | grep -qi "failed to update kubeconfig\|cannot update kubeconfig\|Failed to connect to the CRC VM with SSH"; then
    echo "WARNING: CRC start failed with retryable error (exit code $start_exit_code)"
    if [ $attempt -lt $max_attempts ]; then
      echo "Stopping CRC and retrying..."
      sudo -su $USER crc stop || true
      sleep 10
      attempt=$((attempt + 1))
      continue
    fi
  fi

  echo "ERROR: CRC start failed (exit code $start_exit_code) on attempt $attempt of $max_attempts"
  exit 1
done

# Clean up pull secret immediately after use
rm -f pull-secret.json

echo "=== Disk usage after CRC start ==="
df -h
