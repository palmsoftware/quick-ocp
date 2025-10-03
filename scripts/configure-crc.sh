#!/bin/bash
set -e

CRC_CPU="$1"
CRC_MEMORY="$2"
CRC_DISK_SIZE="$3"
ENABLE_TELEMETRY="$4"

echo "=== Configuring CRC for minimal resource usage ==="
crc config set cpus $CRC_CPU
crc config set memory $CRC_MEMORY
crc config set disk-size $CRC_DISK_SIZE
crc config set consent-telemetry $ENABLE_TELEMETRY
crc config set network-mode user
