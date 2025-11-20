#!/bin/bash
set -e

# Enhanced CRC download script with cache failover
# This version includes a testing flag to simulate mirror failures

CRC_VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Testing flag: Set to "true" to simulate mirror failure for testing cache
SIMULATE_MIRROR_FAILURE="${SIMULATE_MIRROR_FAILURE:-false}"

# Cache configuration
CACHE_REGISTRY="${CACHE_REGISTRY:-quay.io}"
CACHE_IMAGE_NAME="${CACHE_IMAGE_NAME:-bapalm/quick-ocp-cache}"

echo "==========================================="
echo "CRC Download with Cache Failover"
echo "==========================================="
echo "CRC Version: $CRC_VERSION"
echo "Testing Mode: $SIMULATE_MIRROR_FAILURE"
echo ""

# Function to check if cache image exists
check_cache_available() {
  local version="$1"
  local image="${CACHE_REGISTRY}/${CACHE_IMAGE_NAME}:${version}"

  echo "→ Checking if cache is available for version $version..."

  if ! command -v docker &>/dev/null; then
    echo "  ✗ Docker not available (cache requires Docker)"
    return 1
  fi

  if docker manifest inspect "$image" >/dev/null 2>&1; then
    echo "  ✓ Cache image available: $image"
    return 0
  else
    echo "  ✗ Cache image not found: $image"
    return 1
  fi
}

# Function to download from mirror (Tier 1)
download_from_mirror() {
  echo ""
  echo "========================================="
  echo "Tier 1: Attempting download from mirror"
  echo "========================================="

  # Testing: Simulate mirror failure
  if [ "$SIMULATE_MIRROR_FAILURE" = "true" ]; then
    echo "⚠️  TESTING MODE: Simulating mirror failure"
    return 1
  fi

  local max_retries=3
  local retry_count=0
  local download_success=false

  while [ $retry_count -lt $max_retries ]; do
    echo "→ Attempt $((retry_count + 1)) of $max_retries: Downloading CRC version $CRC_VERSION..."

    # Remove any partial download from previous attempt
    rm -f crc.tar.xz

    if curl -L -o crc.tar.xz "https://mirror.openshift.com/pub/openshift-v4/clients/crc/$CRC_VERSION/crc-linux-amd64.tar.xz"; then
      # Verify the downloaded file is valid (should be larger than 1MB)
      FILE_SIZE=$(stat -c%s crc.tar.xz 2>/dev/null || stat -f%z crc.tar.xz 2>/dev/null || echo 0)
      if [ "$FILE_SIZE" -gt 1048576 ]; then
        echo "✓ Download successful from mirror. File size: $FILE_SIZE bytes"
        download_success=true
        break
      else
        echo "✗ Download failed: File too small ($FILE_SIZE bytes), likely an error page"
      fi
    else
      echo "✗ Download failed with curl error"
    fi

    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      echo "  Waiting 10 seconds before retry..."
      sleep 10
    fi
  done

  if [ "$download_success" = false ]; then
    echo ""
    echo "✗ Failed to download CRC from mirror after $max_retries attempts"
    return 1
  fi

  # Extract and install
  echo ""
  echo "→ Extracting and installing from mirror download..."
  tar -xvf crc.tar.xz
  if [ -d crc-linux-* ] && [ -f crc-linux-*/crc ]; then
    sudo mv crc-linux-*/crc /usr/local/bin
    echo "✓ CRC binary installed to /usr/local/bin/crc"
  else
    echo "✗ Error: CRC binary not found in extracted archive"
    return 1
  fi

  # Clean up
  rm -rf crc.tar.xz crc-linux-*

  echo ""
  echo "✓ Mirror download completed successfully"
  return 0
}

# Function to download from cache (Tier 2)
download_from_cache() {
  echo ""
  echo "========================================="
  echo "Tier 2: Attempting download from cache"
  echo "========================================="

  # Check if cache script exists
  if [ ! -f "$SCRIPT_DIR/download-from-cache.sh" ]; then
    echo "✗ Cache download script not found: $SCRIPT_DIR/download-from-cache.sh"
    return 1
  fi

  # Use the dedicated cache download script
  if "$SCRIPT_DIR/download-from-cache.sh" "$CRC_VERSION"; then
    echo ""
    echo "✓ Cache download completed successfully"
    return 0
  else
    echo ""
    echo "✗ Cache download failed"
    return 1
  fi
}

# Main download logic with failover
main() {
  local mirror_success=false
  local cache_success=false

  # Pre-check: Verify cache availability before attempting mirror
  # This helps us know if we have a fallback option
  echo "Pre-flight check:"
  if check_cache_available "$CRC_VERSION"; then
    CACHE_IS_AVAILABLE=true
    echo "  ℹ️  Cache fallback is available if mirror fails"
  else
    CACHE_IS_AVAILABLE=false
    echo "  ⚠️  Cache fallback is NOT available for this version"
    echo "  ⚠️  Mirror download MUST succeed"
  fi

  # Tier 1: Try mirror first (unless testing)
  if download_from_mirror; then
    mirror_success=true
  else
    echo ""
    echo "⚠️  Mirror download failed"

    # Tier 2: Fall back to cache
    if [ "$CACHE_IS_AVAILABLE" = "true" ]; then
      echo "→ Attempting cache fallback..."

      if download_from_cache; then
        cache_success=true
        echo ""
        echo "✓ Successfully recovered using cache"
      fi
    else
      echo "✗ Cache fallback not available"
    fi
  fi

  # Final status
  echo ""
  echo "========================================="
  echo "Download Summary"
  echo "========================================="

  if [ "$mirror_success" = true ]; then
    echo "Status: ✓ SUCCESS"
    echo "Source: Primary mirror"
    echo "CRC Version: $CRC_VERSION"
  elif [ "$cache_success" = true ]; then
    echo "Status: ✓ SUCCESS (via cache failover)"
    echo "Source: Cache image (${CACHE_REGISTRY}/${CACHE_IMAGE_NAME}:${CRC_VERSION})"
    echo "CRC Version: $CRC_VERSION"
    echo ""
    echo "ℹ️  Note: Primary mirror was unavailable, cache was used as fallback"
  else
    echo "Status: ✗ FAILED"
    echo "Reason: All download sources failed"
    echo ""
    echo "Attempted:"
    echo "  1. Primary mirror - FAILED"
    if [ "$CACHE_IS_AVAILABLE" = "true" ]; then
      echo "  2. Cache fallback - FAILED"
    else
      echo "  2. Cache fallback - NOT AVAILABLE"
    fi
    echo ""
    echo "Troubleshooting:"
    echo "  - Check network connectivity"
    echo "  - Verify CRC version $CRC_VERSION exists"
    echo "  - Check cache builder status: https://quay.io/repository/${CACHE_IMAGE_NAME}?tab=tags"
    exit 1
  fi

  echo ""
  echo "=== Disk usage after CRC download ==="
  df -h
}

# Run main function
main
