#!/bin/bash
set -e

echo "=== Running CRC setup ==="
sudo -su $USER crc setup --log-level debug --show-progressbars

echo "=== Disk usage after CRC setup ==="
df -h

echo "=== Starting CRC ==="
sudo -su $USER crc start --pull-secret-file pull-secret.json --log-level debug

# Clean up pull secret immediately after use
rm -f pull-secret.json

echo "=== Disk usage after CRC start ==="
df -h
