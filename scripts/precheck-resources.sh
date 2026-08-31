#!/bin/bash
set -e

gha_error() {
  echo "::error::$1" >&2
  echo "[ERROR] $1" >&2
}

CRC_CPU="$1"
CRC_MEMORY="$2"
ENABLE_CLUSTER_MONITORING="$3"

echo "=== Prechecking runner resources for CRC deployment ==="

# Keep in sync with configure-crc.sh
MIN_MONITORING_MEMORY=14336
if [ "$ENABLE_CLUSTER_MONITORING" = "true" ]; then
  if [ "$CRC_MEMORY" -lt "$MIN_MONITORING_MEMORY" ]; then
    CRC_MEMORY=$MIN_MONITORING_MEMORY
  fi
fi

MIN_TOTAL_DISK_GB=50
CRITICAL_MEMORY_MB=4096

PRECHECK_OK=true
FAILED_CHECKS=()
WARNINGS=()

check_cpu() {
  local required="$1"
  local available
  available=$(nproc)

  echo -n "Checking CPU count... "
  if [ "$available" -lt "$required" ]; then
    echo "✗ FAILED ($available available, $required required)"
    PRECHECK_OK=false
    FAILED_CHECKS+=("CPU: runner has $available CPUs but CRC requires $required")
  else
    echo "✓ OK ($available available, $required required)"
  fi
}

check_memory() {
  local required="$1"
  local total_mb
  total_mb=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)

  echo -n "Checking memory... "
  if [ "$total_mb" -lt "$CRITICAL_MEMORY_MB" ]; then
    echo "✗ FAILED (${total_mb}MB available, minimum ${CRITICAL_MEMORY_MB}MB)"
    PRECHECK_OK=false
    FAILED_CHECKS+=("Memory: runner has ${total_mb}MB RAM which is below the ${CRITICAL_MEMORY_MB}MB minimum (even with swap)")
  elif [ "$total_mb" -lt "$required" ]; then
    echo "✓ OK with warning (${total_mb}MB physical, ${required}MB requested)"
    WARNINGS+=("Memory: runner has ${total_mb}MB physical RAM but CRC will request ${required}MB. The action creates 8GB swap to compensate, but expect slower performance.")
  else
    echo "✓ OK (${total_mb}MB available, ${required}MB requested)"
  fi
}

check_mnt_directory() {
  echo -n "Checking /mnt directory... "
  if [ ! -d /mnt ]; then
    echo "✗ FAILED (/mnt does not exist)"
    PRECHECK_OK=false
    FAILED_CHECKS+=("/mnt: directory does not exist. CRC storage, swap, and Docker are relocated to /mnt. Standard GitHub runners provide this; self-hosted runners may need to create /mnt.")
  elif ! sudo touch /mnt/.precheck-test 2>/dev/null; then
    echo "✗ FAILED (/mnt is not writable)"
    PRECHECK_OK=false
    FAILED_CHECKS+=("/mnt: directory exists but is not writable. CRC storage, swap, and Docker are relocated to /mnt and require write access.")
  else
    sudo rm -f /mnt/.precheck-test
    echo "✓ OK"
  fi
}

check_disk_capacity() {
  local min_total="$1"
  local root_total_gb mnt_total_gb total_gb
  local root_device mnt_device

  root_total_gb=$(df --output=size -BG / | tail -1 | tr -d 'G ')
  root_device=$(df --output=source / | tail -1)

  mnt_total_gb=0
  if [ -d /mnt ]; then
    mnt_device=$(df --output=source /mnt 2>/dev/null | tail -1)
    if [ "$mnt_device" != "$root_device" ]; then
      mnt_total_gb=$(df --output=size -BG /mnt | tail -1 | tr -d 'G ')
    fi
  fi

  total_gb=$((root_total_gb + mnt_total_gb))

  echo -n "Checking total disk capacity... "
  if [ "$total_gb" -lt "$min_total" ]; then
    echo "✗ FAILED (${total_gb}GB total, ${min_total}GB minimum)"
    PRECHECK_OK=false
    FAILED_CHECKS+=("Disk: combined root + /mnt capacity is ${total_gb}GB but at least ${min_total}GB is required (root: ${root_total_gb}GB, /mnt: ${mnt_total_gb}GB)")
  else
    echo "✓ OK (${total_gb}GB total across root: ${root_total_gb}GB, /mnt: ${mnt_total_gb}GB)"
  fi
}

check_cpu "$CRC_CPU"
check_memory "$CRC_MEMORY"
check_mnt_directory
check_disk_capacity "$MIN_TOTAL_DISK_GB"

echo ""
echo "=== Resource Precheck Summary ==="

if [ ${#WARNINGS[@]} -gt 0 ]; then
  for warning in "${WARNINGS[@]}"; do
    echo "WARNING: $warning"
  done
  echo ""
fi

if [ "$PRECHECK_OK" = true ]; then
  echo "✓ All resource prechecks passed"
  echo ""
  exit 0
else
  echo "✗ Resource precheck FAILED"
  echo ""
  echo "The following requirements are not met:"
  for check in "${FAILED_CHECKS[@]}"; do
    gha_error "Resource precheck: $check"
    echo "  - $check"
  done
  echo ""
  echo "Suggestions:"
  echo "  - Use a GitHub-hosted runner with more resources"
  echo "  - Reduce resource requests via crcCpu, crcMemory, or crcDiskSize inputs"
  echo "  - Set disableResourcePrecheck: true to skip this check (not recommended)"
  echo ""
  exit 1
fi
