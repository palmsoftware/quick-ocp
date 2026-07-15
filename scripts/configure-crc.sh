#!/bin/bash
set -e

CRC_CPU="$1"
CRC_MEMORY="$2"
CRC_DISK_SIZE="$3"
ENABLE_TELEMETRY="$4"
ENABLE_CLUSTER_MONITORING="$5"

validate_numeric() {
  local name="$1"
  local value="$2"
  local min="$3"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "ERROR: $name must be a positive integer, got: '$value'" >&2
    exit 1
  fi
  if [ "$value" -lt "$min" ]; then
    echo "ERROR: $name must be at least $min, got: $value" >&2
    exit 1
  fi
}

validate_numeric "crcCpu" "$CRC_CPU" 4
validate_numeric "crcMemory" "$CRC_MEMORY" 10752
validate_numeric "crcDiskSize" "$CRC_DISK_SIZE" 31

MIN_MONITORING_MEMORY=14336

if [ "$ENABLE_CLUSTER_MONITORING" = "true" ]; then
  if [ "$CRC_MEMORY" -lt "$MIN_MONITORING_MEMORY" ]; then
    echo "=== Cluster monitoring requires ${MIN_MONITORING_MEMORY}MB memory, increasing from ${CRC_MEMORY}MB ==="
    CRC_MEMORY=$MIN_MONITORING_MEMORY
  fi
fi

echo "=== Configuring CRC for minimal resource usage ==="
crc config set cpus "$CRC_CPU"
crc config set memory "$CRC_MEMORY"
crc config set disk-size "$CRC_DISK_SIZE"
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

if [ -n "${HTTP_PROXY_INPUT:-}" ]; then
  echo "=== Configuring HTTP proxy ==="
  crc config set http-proxy "$HTTP_PROXY_INPUT"
fi
if [ -n "${HTTPS_PROXY_INPUT:-}" ]; then
  echo "=== Configuring HTTPS proxy ==="
  crc config set https-proxy "$HTTPS_PROXY_INPUT"
fi
if [ -n "${NO_PROXY_INPUT:-}" ]; then
  echo "=== Configuring no-proxy list ==="
  crc config set no-proxy "$NO_PROXY_INPUT"
fi
if [ -n "${PROXY_CA_FILE_INPUT:-}" ]; then
  echo "=== Configuring proxy CA file ==="
  crc config set proxy-ca-file "$PROXY_CA_FILE_INPUT"
fi
