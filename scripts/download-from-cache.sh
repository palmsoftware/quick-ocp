#!/bin/bash
set -e

# Download CRC from cached container image
# This script includes safeguards to verify image exists before attempting download

CRC_VERSION="$1"
REGISTRY="${CACHE_REGISTRY:-quay.io}"
IMAGE_NAME="${CACHE_IMAGE_NAME:-bapalm/quick-ocp-cache}"

if [ -z "$CRC_VERSION" ]; then
  echo "ERROR: CRC version not specified"
  echo "Usage: $0 <CRC_VERSION>"
  exit 1
fi

IMAGE_TAG="${REGISTRY}/${IMAGE_NAME}:${CRC_VERSION}"

echo "========================================="
echo "Attempting to download CRC from cache"
echo "========================================="
echo "CRC Version: $CRC_VERSION"
echo "Cache Image: $IMAGE_TAG"
echo ""

# Safeguard 1: Check if Docker/Podman is available
if ! command -v docker &>/dev/null; then
  echo "ERROR: Docker is not available"
  echo "Cache download requires Docker or Podman"
  exit 1
fi

# Safeguard 2: Check if image exists before attempting to pull
echo "→ Verifying cache image exists..."
if ! docker manifest inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  echo "ERROR: Cache image not found: $IMAGE_TAG"
  echo ""
  echo "Available cache versions can be checked at:"
  echo "  https://quay.io/repository/${IMAGE_NAME}?tab=tags"
  echo ""
  echo "This usually means:"
  echo "  1. The CRC version $CRC_VERSION hasn't been cached yet"
  echo "  2. The cache builder hasn't run for this version"
  echo "  3. The image tag doesn't match (check spelling/format)"
  exit 1
fi

echo "✓ Cache image exists"
echo ""

# Safeguard 3: Check available disk space (need ~500MB for extraction)
AVAILABLE_SPACE=$(df -k . | awk 'NR==2 {print $4}')
REQUIRED_SPACE=512000 # 500MB in KB

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
  echo "WARNING: Low disk space"
  echo "Available: $((AVAILABLE_SPACE / 1024)) MB"
  echo "Required: $((REQUIRED_SPACE / 1024)) MB"
  echo ""
fi

# Pull the image
echo "→ Pulling cache image..."
if ! docker pull "$IMAGE_TAG"; then
  echo "ERROR: Failed to pull cache image"
  echo "This might be a temporary network issue or registry problem"
  exit 1
fi

echo "✓ Cache image pulled successfully"
echo ""

# Create temporary container to extract files
echo "→ Creating temporary container..."
CONTAINER_ID=$(docker create "$IMAGE_TAG")

cleanup() {
  echo "→ Cleaning up temporary container..."
  docker rm "$CONTAINER_ID" >/dev/null 2>&1 || true
}

trap cleanup EXIT

# Extract CRC binary
echo "→ Extracting CRC binary..."
if ! docker cp "$CONTAINER_ID:/cache/crc-linux-amd64.tar.xz" ./crc.tar.xz 2>/dev/null; then
  echo "ERROR: Failed to extract CRC binary from cache image"
  echo "The cache image may be corrupted or have an unexpected structure"
  exit 1
fi

# Verify the extracted file
FILE_SIZE=$(stat -c%s crc.tar.xz 2>/dev/null || stat -f%z crc.tar.xz 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -lt 1048576 ]; then
  echo "ERROR: Extracted file is too small ($FILE_SIZE bytes)"
  echo "The cache image may be corrupted"
  rm -f crc.tar.xz
  exit 1
fi

echo "✓ CRC binary extracted (${FILE_SIZE} bytes)"
echo ""

# Extract and install
echo "→ Extracting and installing CRC..."
tar -xvf crc.tar.xz

if [ -d crc-linux-* ] && [ -f crc-linux-*/crc ]; then
  sudo mv crc-linux-*/crc /usr/local/bin
  echo "✓ CRC binary installed to /usr/local/bin/crc"
else
  echo "ERROR: CRC binary not found in extracted archive"
  ls -la
  exit 1
fi

# Clean up
rm -rf crc.tar.xz crc-linux-*

echo ""
echo "========================================="
echo "✓ Cache download completed successfully"
echo "========================================="
echo "CRC Version: $CRC_VERSION"
echo "Source: $IMAGE_TAG"
echo ""

# Verify installation
if command -v crc &>/dev/null; then
  echo "CRC version installed:"
  crc version | head -1 || true
fi

echo ""
df -h
