#!/bin/bash
set -eo pipefail

REGISTRY="quay.io"
IMAGE="bapalm/quick-ocp-cache"
PINS_FILE="${PINS_FILE:-$(dirname "$0")/../crc-version-pins.json}"

if [ ! -f "$PINS_FILE" ]; then
  echo "::error::Pins file not found: ${PINS_FILE}"
  exit 1
fi

MISSING=()

while IFS= read -r OCP_VERSION; do
  for ARCH in amd64 arm64; do
    TAG="${REGISTRY}/${IMAGE}:${OCP_VERSION}-${ARCH}"
    if docker manifest inspect "${TAG}" >/dev/null 2>&1; then
      echo "✓ ${TAG}"
    else
      echo "::error::Missing cache image: ${TAG}"
      MISSING+=("${TAG}")
    fi
  done
done < <(jq -r '.version_pins | keys[] | select(. != "latest")' "$PINS_FILE")

if [ ${#MISSING[@]} -gt 0 ]; then
  echo ""
  echo "Missing images:"
  printf '  %s\n' "${MISSING[@]}"
  echo ""
  echo "Build missing images via workflow_dispatch on palmsoftware/quick-ocp-cache."
  exit 1
fi

echo "All cache images present."
