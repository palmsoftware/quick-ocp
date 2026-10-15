#!/bin/bash
set -eo pipefail

# Verifies the content of the Quay image cache for one OCP minor + arch
# against what quick-ocp would actually install at runtime: the pinned CRC
# version and the exact bundle z-version embedded in that crc binary.
# check-image-cache.sh only asserts the tags exist; this catches a builder
# that has drifted (e.g. an image carrying a bundle for the wrong z-version,
# which crc setup would refuse and re-download from the mirror).
#
# Requires:
#   OCP_VERSION - the OCP minor to verify (e.g. 4.20)
# Optional:
#   ARCH           - architecture to verify (default: this machine's)
#   CRC_VERSION    - skip pin resolution, verify against this CRC version
#   CRC_BINARY_DIR - directory containing a `crc` binary to query instead of
#                    downloading the pinned release from the mirror
#   PINS_FILE      - path to crc-version-pins.json
#   GITHUB_TOKEN   - raises the GitHub API rate limit for pin resolution

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../crc-version-pins.json}"

OCP_VERSION="${OCP_VERSION:-}"
if [ -z "$OCP_VERSION" ]; then
  echo "::error::OCP_VERSION env var is required (e.g. 4.20)"
  exit 1
fi

# MACHINE_ARCH is this machine's docker arch; the downloaded crc binary must
# run here even when ARCH selects another platform's image.
MACHINE_ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
ARCH="${ARCH:-${MACHINE_ARCH}}"

IMAGE_REGISTRY="quay.io"
IMAGE_NAME="bapalm/quick-ocp-cache"
IMAGE_TAG="${IMAGE_REGISTRY}/${IMAGE_NAME}:${OCP_VERSION}-${ARCH}"

if [ ! -f "$PINS_FILE" ]; then
  echo "::error::Pins file not found: ${PINS_FILE}"
  exit 1
fi

WORK_DIR=$(mktemp -d)
CONTAINER_ID=""
cleanup() {
  if [ -n "${CONTAINER_ID}" ]; then
    docker rm -f "${CONTAINER_ID}" >/dev/null 2>&1 || true
  fi
  docker rmi "${IMAGE_TAG}" >/dev/null 2>&1 || true
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# --- 1. Resolve the CRC version quick-ocp would install for this minor ---
if [ -n "${CRC_VERSION:-}" ]; then
  PINNED_CRC="${CRC_VERSION}"
else
  PIN=$(jq -r --arg v "${OCP_VERSION}" '.version_pins[$v] // empty' "${PINS_FILE}")
  if [ -z "${PIN}" ]; then
    echo "::warning::No pin entry for OCP ${OCP_VERSION} in ${PINS_FILE} — nothing to verify"
    exit 0
  fi

  if [ "${PIN}" = "auto" ]; then
    # Mirrors set-crc-version.sh's runtime resolution. That script prints
    # error sentinels ("latest", "No CRC release found for OpenShift ...")
    # to stdout with exit 0, so guard them the same way it does.
    PINNED_CRC=$("${SCRIPT_DIR}/fetch-ocp-crc-version.sh" "${OCP_VERSION}")
    if [ -z "${PINNED_CRC}" ] || [ "${PINNED_CRC}" = "latest" ] ||
      [[ "${PINNED_CRC}" == No* ]] || [[ "${PINNED_CRC}" == Error* ]]; then
      echo "::warning::Could not resolve the CRC release serving OCP ${OCP_VERSION} — skipping verification"
      exit 0
    fi
  else
    PINNED_CRC="${PIN}"
  fi
fi
echo "=== Verifying ${IMAGE_TAG} against CRC ${PINNED_CRC} ==="

# Fail fast on a missing image, before the crc binary download.
if ! docker manifest inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
  echo "::error::Missing cache image: ${IMAGE_TAG}. Build it via workflow_dispatch on palmsoftware/quick-ocp-cache."
  exit 1
fi

# --- 2. Expected bundle z-version: the one embedded in that crc binary ---
if [ -n "${CRC_BINARY_DIR:-}" ] && [ -x "${CRC_BINARY_DIR}/crc" ]; then
  CRC_BIN="${CRC_BINARY_DIR}/crc"
else
  if [ "$(uname -s)" != "Linux" ]; then
    echo "::error::Downloading the CRC binary is only supported on Linux — set CRC_BINARY_DIR to a directory containing the crc ${PINNED_CRC} binary"
    exit 1
  fi
  echo "Downloading crc ${PINNED_CRC} (${MACHINE_ARCH}) from the mirror..."
  if ! curl -fsSL --retry 3 -o "${WORK_DIR}/crc.tar.xz" \
    "https://mirror.openshift.com/pub/openshift-v4/clients/crc/${PINNED_CRC}/crc-linux-${MACHINE_ARCH}.tar.xz"; then
    echo "::error::Failed to download crc ${PINNED_CRC} from the mirror — cannot determine the expected bundle version"
    exit 1
  fi
  tar -xf "${WORK_DIR}/crc.tar.xz" -C "${WORK_DIR}"
  CRC_BIN=$(find "${WORK_DIR}" -maxdepth 2 -type f -name crc -print -quit)
  if [ -z "${CRC_BIN}" ]; then
    echo "::error::crc binary not found in the downloaded archive"
    exit 1
  fi
  chmod +x "${CRC_BIN}"
fi

EXPECTED_Z=$("${CRC_BIN}" version -o json | jq -r '.openshiftVersion')
if [ -z "${EXPECTED_Z}" ] || [ "${EXPECTED_Z}" = "null" ]; then
  echo "::error::Could not read the embedded OpenShift version from the crc ${PINNED_CRC} binary"
  exit 1
fi
EXPECTED_BUNDLE_NAME="crc_libvirt_${EXPECTED_Z}_${ARCH}.crcbundle"
echo "crc ${PINNED_CRC} embeds OpenShift ${EXPECTED_Z} → expected bundle: ${EXPECTED_BUNDLE_NAME}"

# --- 3. Pull the image and read its metadata ---
if ! docker pull --platform "linux/${ARCH}" "${IMAGE_TAG}"; then
  echo "::error::Failed to pull ${IMAGE_TAG}. Rebuild it via workflow_dispatch on palmsoftware/quick-ocp-cache."
  exit 1
fi
if ! CONTAINER_ID=$(docker create --platform "linux/${ARCH}" "${IMAGE_TAG}"); then
  echo "::error::Failed to create a container from ${IMAGE_TAG}. Rebuild it via workflow_dispatch on palmsoftware/quick-ocp-cache."
  exit 1
fi
if ! docker cp "${CONTAINER_ID}:/cache/metadata.json" "${WORK_DIR}/metadata.json"; then
  echo "::error::metadata.json not found in ${IMAGE_TAG}. Rebuild it via workflow_dispatch on palmsoftware/quick-ocp-cache."
  exit 1
fi

if ! jq empty "${WORK_DIR}/metadata.json" >/dev/null 2>&1; then
  echo "::error::metadata.json in ${IMAGE_TAG} is not valid JSON. Rebuild it via workflow_dispatch on palmsoftware/quick-ocp-cache."
  exit 1
fi

# --- 4. Assert the metadata matches the runtime contract ---
FAILURES=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [ "${expected}" = "${actual}" ]; then
    echo "  ✓ ${label}: ${actual}"
  else
    echo "  ✗ ${label}: expected ${expected}, got ${actual}"
    FAILURES=$((FAILURES + 1))
  fi
}

check "ocp_version" "${OCP_VERSION}" "$(jq -r '.ocp_version' "${WORK_DIR}/metadata.json")"
check "architecture" "${ARCH}" "$(jq -r '.architecture' "${WORK_DIR}/metadata.json")"
check "crc_version" "${PINNED_CRC}" "$(jq -r '.crc_version' "${WORK_DIR}/metadata.json")"
check "bundle_name" "${EXPECTED_BUNDLE_NAME}" "$(jq -r '.bundle_name' "${WORK_DIR}/metadata.json")"

BUNDLE_SIZE=$(jq -r '.bundle_size // 0' "${WORK_DIR}/metadata.json")
MIN_BUNDLE_SIZE=$((1024 * 1024 * 1024))
if [ "${BUNDLE_SIZE}" -ge "${MIN_BUNDLE_SIZE}" ]; then
  echo "  ✓ bundle_size: ${BUNDLE_SIZE} bytes"
else
  echo "  ✗ bundle_size: ${BUNDLE_SIZE} bytes, expected at least ${MIN_BUNDLE_SIZE}"
  FAILURES=$((FAILURES + 1))
fi

if [ "${FAILURES}" -ne 0 ]; then
  echo ""
  echo "::error::${IMAGE_TAG} does not match the runtime contract (${FAILURES} mismatch(es)). Rebuild it via workflow_dispatch on palmsoftware/quick-ocp-cache."
  exit 1
fi

echo "=== ${IMAGE_TAG} matches the runtime contract ==="
