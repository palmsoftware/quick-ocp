#!/bin/bash
set -eo pipefail

# Pulls the CRC bundle from the Quay image cache so crc setup does not
# have to download it from the OpenShift mirror (slow, rate-limited, and
# the least reliable phase of cluster deployment).
#
# Usage: pull-bundle-from-image-cache.sh [preseed|fallback]
#
# Modes:
#   preseed  — called before crc setup. Every failure is non-fatal
#              (warning + exit 0) so the job degrades to the normal
#              mirror download. Writes result=<value> to $GITHUB_OUTPUT,
#              one of: preseeded, skipped-existing, skipped-stale,
#              skipped-unavailable, failed.
#   fallback — called after a crc setup failure (default). Preserves the
#              original semantics: exit 1 on failure so dependent retry
#              steps are skipped.
#
# Requires:
#   OCP_VERSION - the OCP minor to pull (e.g. 4.20)
# Optional:
#   EXPECTED_OCP_Z_VERSION - exact z-version embedded in the installed crc
#                            binary (e.g. 4.20.5). When set and parseable,
#                            the Quay tag is keyed to its minor (so
#                            desiredOCPVersion: latest maps to the concrete
#                            minor's image) and a bundle that does not match
#                            is treated as stale and deleted rather than
#                            trusted.
#   PRESEED_RESULT - result the pre-seed step reported; 'skipped-stale'
#                    makes fallback mode fail without re-pulling an image
#                    already proven stale

MODE="${1:-fallback}"
if [ "$MODE" != "preseed" ] && [ "$MODE" != "fallback" ]; then
  echo "::error::Usage: $0 [preseed|fallback] (got '${MODE}')"
  exit 1
fi

IMAGE_REGISTRY="quay.io"
IMAGE_NAME="bapalm/quick-ocp-cache"
OCP_VERSION="${OCP_VERSION:-}"

if [ -z "$OCP_VERSION" ]; then
  echo "::error::OCP_VERSION env var is required"
  exit 1
fi

ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
CACHE_DIR="$HOME/.crc/cache"
STAGED_TAR="/tmp/bundle.tar"
EXPECTED_OCP_Z_VERSION="${EXPECTED_OCP_Z_VERSION:-}"

# Key the image tag off the z-version the resolved crc binary embeds when
# known: for a pinned minor it matches OCP_VERSION, and for
# desiredOCPVersion: latest it maps the pointer to the concrete minor
# (e.g. latest → 4.22.14 → the 4.22 image). Arch-suffixed tags are the
# surface CI validates (check-image-cache.sh, verify-image-cache-content.sh);
# the bare minor tag is only a manifest list.
TAG_MINOR="${OCP_VERSION}"
if [[ "$EXPECTED_OCP_Z_VERSION" =~ ^4\.[0-9]+\.[0-9]+$ ]]; then
  TAG_MINOR="${EXPECTED_OCP_Z_VERSION%.*}"
fi
IMAGE_TAG="${IMAGE_REGISTRY}/${IMAGE_NAME}:${TAG_MINOR}-${ARCH}"

set_result() {
  if [ "$MODE" = "preseed" ] && [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "result=$1" >>"$GITHUB_OUTPUT"
  fi
}

# Mode-aware failure: preseed degrades to the mirror path (warning + exit 0),
# fallback keeps the original exit 1 so dependent retry steps are skipped.
fail() {
  local result="$1"
  shift
  if [ "$MODE" = "preseed" ]; then
    echo "::warning::$* — falling back to the OpenShift mirror for the bundle download"
    set_result "$result"
    exit 0
  fi
  echo "::error::$*"
  exit 1
}

find_bundle() {
  find -L "${CACHE_DIR}" -maxdepth 1 -name "*.crcbundle" -print -quit 2>/dev/null || true
}

CONTAINER_ID=""
PULLED=false
cleanup() {
  if [ -n "${CONTAINER_ID}" ]; then
    docker rm -f "${CONTAINER_ID}" 2>/dev/null || true
  fi
  # Reclaim the image layers (~7 GB) — they compete with the CRC VM disk for
  # space once setup and start run. Only images we actually pulled.
  if [ "${PULLED}" = true ]; then
    docker rmi "${IMAGE_TAG}" 2>/dev/null || true
  fi
  # The staged tar (~5.7 GB) is removed after extraction; clear it on
  # failure paths too so it cannot fill the root disk.
  rm -f "${STAGED_TAR}"
}
trap cleanup EXIT

echo "=== Checking for existing bundle in ${CACHE_DIR} ==="
if [ -n "$(find_bundle)" ]; then
  if [ "$MODE" = "preseed" ]; then
    echo "Bundle already present in ${CACHE_DIR} — skipping image cache pre-seed"
  else
    echo "Bundle already present in ${CACHE_DIR} — setup failure was not due to missing bundle"
    echo "Allowing retry of CRC setup and start"
  fi
  set_result "skipped-existing"
  exit 0
fi

echo "=== No bundle found — pulling from Quay image cache (${MODE} mode) ==="
echo "OCP version: ${OCP_VERSION}, arch: ${ARCH}"
echo "Image: ${IMAGE_TAG}"

# The pre-seed already extracted this exact image and deleted its stale
# bundle; re-pulling cannot change the outcome.
if [ "$MODE" = "fallback" ] && [ "${PRESEED_RESULT:-}" = "skipped-stale" ]; then
  echo "::error::Quay image ${IMAGE_TAG} was already found stale by the pre-seed and crc setup failed on the mirror — rebuild the image via workflow_dispatch on palmsoftware/quick-ocp-cache"
  exit 1
fi

if ! docker manifest inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
  fail "skipped-unavailable" "Quay image ${IMAGE_TAG} not found — no image cache available for OCP ${OCP_VERSION}"
fi

echo "=== Pulling bundle from ${IMAGE_TAG} (platform linux/${ARCH}) ==="
if ! docker pull --platform "linux/${ARCH}" "${IMAGE_TAG}"; then
  fail "failed" "Failed to pull ${IMAGE_TAG}"
fi
PULLED=true

if ! CONTAINER_ID=$(docker create --platform "linux/${ARCH}" "${IMAGE_TAG}"); then
  fail "failed" "Failed to create container from ${IMAGE_TAG}"
fi

mkdir -p "${CACHE_DIR}"
if ! docker cp "${CONTAINER_ID}:/cache/bundle.tar" "${STAGED_TAR}"; then
  fail "failed" "Failed to copy bundle.tar out of ${IMAGE_TAG}"
fi
if ! tar -xf "${STAGED_TAR}" -C "${CACHE_DIR}/"; then
  fail "failed" "Failed to extract bundle.tar into ${CACHE_DIR}"
fi

BUNDLE_FILE=$(find_bundle)
if [ -z "${BUNDLE_FILE}" ]; then
  fail "failed" "Bundle extraction from Quay image failed — no .crcbundle found in ${CACHE_DIR}"
fi

# Freshness: crc setup only accepts a pre-placed bundle named for the exact
# z-version embedded in the crc binary, so a stale cached bundle is worse
# than none — setup would re-download it anyway. When the expected version
# is missing or unparseable, keep the bundle rather than delete a
# possibly-good one on a lookup failure.
if [ -n "$EXPECTED_OCP_Z_VERSION" ] && [[ "$EXPECTED_OCP_Z_VERSION" =~ ^4\.[0-9]+\.[0-9]+$ ]]; then
  EXPECTED_BUNDLE_NAME="crc_libvirt_${EXPECTED_OCP_Z_VERSION}_${ARCH}.crcbundle"
  if [ "$(basename "$BUNDLE_FILE")" != "$EXPECTED_BUNDLE_NAME" ]; then
    echo "::warning::Image cache is stale: expected ${EXPECTED_BUNDLE_NAME} (z-version embedded in the crc binary) but found $(basename "$BUNDLE_FILE")"
    rm -f "$BUNDLE_FILE"
    fail "skipped-stale" "Image cache bundle for OCP ${OCP_VERSION} does not match the version required by the installed crc binary"
  fi
fi

BUNDLE_SIZE=$(du -m "${BUNDLE_FILE}" | cut -f1)
if [ "${BUNDLE_SIZE}" -lt 1024 ]; then
  fail "failed" "Extracted bundle ${BUNDLE_FILE} is too small (${BUNDLE_SIZE}MB < 1024MB) — likely corrupt"
fi

echo "=== Bundle extracted successfully: ${BUNDLE_FILE} (${BUNDLE_SIZE}MB) ==="
set_result "preseeded"
