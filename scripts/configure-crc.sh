#!/bin/bash
set -e

CRC_CPU="$1"
CRC_MEMORY="$2"
CRC_DISK_SIZE="$3"
ENABLE_TELEMETRY="$4"
ENABLE_CLUSTER_MONITORING="$5"

MIN_MONITORING_MEMORY=14336

if [ "$ENABLE_CLUSTER_MONITORING" = "true" ]; then
  if [ "$CRC_MEMORY" -lt "$MIN_MONITORING_MEMORY" ]; then
    echo "=== Cluster monitoring requires ${MIN_MONITORING_MEMORY}MB memory, increasing from ${CRC_MEMORY}MB ==="
    CRC_MEMORY=$MIN_MONITORING_MEMORY
  fi
fi

echo "=== Configuring CRC for minimal resource usage ==="
crc config set cpus $CRC_CPU
crc config set memory $CRC_MEMORY
crc config set disk-size $CRC_DISK_SIZE
if [ "$ENABLE_TELEMETRY" = "true" ]; then
  crc config set consent-telemetry yes
elif [ "$ENABLE_TELEMETRY" = "false" ]; then
  crc config set consent-telemetry no
else
  echo "WARNING: enableTelemetry='$ENABLE_TELEMETRY' is not 'true' or 'false', treating as false"
  crc config set consent-telemetry no
fi
crc config set network-mode user

if [ "$ENABLE_CLUSTER_MONITORING" = "true" ]; then
  echo "=== Enabling cluster monitoring stack ==="
  crc config set enable-cluster-monitoring true
fi
