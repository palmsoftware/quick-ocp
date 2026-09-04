#!/bin/bash
set -eo pipefail

IMAGE_REGISTRY="quay.io"
IMAGE_NAME="bapalm/quick-ocp-cache"
OCP_VERSION="${OCP_VERSION:-}"

if [ -z "$OCP_VERSION" ]; then
  echo "::error::OCP_VERSION env var is required"
  exit 1
fi

# Normalize YAML float issue (e.g. 4.2 -> 4.20)
if [[ "$OCP_VERSION" =~ ^4\.([2-9])$ ]]; then
  OCP_VERSION="4.${BASH_REMATCH[1]}0"
fi

ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
CACHE_DIR="$HOME/.crc/cache"
IMAGE_TAG="${IMAGE_REGISTRY}/${IMAGE_NAME}:${OCP_VERSION}"

echo "=== Checking for existing bundle in ${CACHE_DIR} ==="
if find "${CACHE_DIR}" -maxdepth 1 -name "*.crcbundle" 2>/dev/null | head -1 | grep -q .; then
  echo "Bundle already present in ${CACHE_DIR} — setup failure was not due to missing bundle"
  echo "Allowing retry of CRC setup and start"
  exit 0
fi

echo "=== No bundle found — attempting Quay image cache fallback ==="
echo "OCP version: ${OCP_VERSION}, arch: ${ARCH}"
echo "Image: ${IMAGE_TAG}"

if ! docker manifest inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
  echo "::warning::Quay image ${IMAGE_TAG} not found — no image cache fallback available for OCP ${OCP_VERSION}"
  exit 1
fi

echo "=== Pulling bundle from ${IMAGE_TAG} (platform linux/${ARCH}) ==="
docker pull --platform "linux/${ARCH}" "${IMAGE_TAG}"

CONTAINER_ID=$(docker create --platform "linux/${ARCH}" "${IMAGE_TAG}")
trap 'docker rm -f "${CONTAINER_ID}" 2>/dev/null || true' EXIT

mkdir -p "${CACHE_DIR}"
docker cp "${CONTAINER_ID}:/cache/bundle.tar" /tmp/bundle.tar
tar -xf /tmp/bundle.tar -C "${CACHE_DIR}/"
rm /tmp/bundle.tar

BUNDLE_FILE=$(find "${CACHE_DIR}" -maxdepth 1 -name "*.crcbundle" 2>/dev/null | head -1)
if [ -z "${BUNDLE_FILE}" ]; then
  echo "::error::Bundle extraction from Quay image failed — no .crcbundle found in ${CACHE_DIR}"
  exit 1
fi

BUNDLE_SIZE=$(du -m "${BUNDLE_FILE}" | cut -f1)
if [ "${BUNDLE_SIZE}" -lt 1024 ]; then
  echo "::error::Extracted bundle ${BUNDLE_FILE} is too small (${BUNDLE_SIZE}MB < 1024MB) — likely corrupt"
  exit 1
fi

echo "=== Bundle extracted successfully: ${BUNDLE_FILE} (${BUNDLE_SIZE}MB) ==="
