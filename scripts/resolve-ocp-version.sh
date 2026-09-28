#!/usr/bin/env bash
set -e

gha_error() {
  echo "::error::$1" >&2
  echo "[ERROR] $1" >&2
}

REQUESTED_VERSION="${1:-}"
ACTION_PATH="${2:-}"
EFFECTIVE_VERSION="$REQUESTED_VERSION"
CRC_VERSION_OVERRIDE="${CRC_VERSION_OVERRIDE:-}"

# YAML parses 4.20 as 4.2, so normalize it before validation and version selection.
if [[ "$EFFECTIVE_VERSION" =~ ^4\.([0-9]+)$ ]]; then
  MINOR_VERSION="${BASH_REMATCH[1]}"
  if [ "${#MINOR_VERSION}" -eq 1 ] && [ "$MINOR_VERSION" -ge 2 ]; then
    EFFECTIVE_VERSION="4.${MINOR_VERSION}0"
    echo "Normalized version from 4.$MINOR_VERSION to $EFFECTIVE_VERSION (YAML float parsing fix)"
  fi
fi

DEPRECATED_VERSION=""
if [ -n "$ACTION_PATH" ] && [ -f "$ACTION_PATH/crc-version-pins.json" ]; then
  DEPRECATED_VERSION=$(jq -r --arg version "$EFFECTIVE_VERSION" '.deprecated_versions[$version] // empty' "$ACTION_PATH/crc-version-pins.json")
fi

if [ -n "$DEPRECATED_VERSION" ]; then
  EFFECTIVE_VERSION="$DEPRECATED_VERSION"
  if [ -n "$CRC_VERSION_OVERRIDE" ]; then
    echo "::warning::desiredOCPVersion $REQUESTED_VERSION is deprecated and will use $EFFECTIVE_VERSION. The crcVersion override was ignored."
  else
    echo "::warning::desiredOCPVersion $REQUESTED_VERSION is deprecated and will use $EFFECTIVE_VERSION."
  fi

  CRC_VERSION_OVERRIDE=""
fi

if [ "$EFFECTIVE_VERSION" != "latest" ] && [[ ! "$EFFECTIVE_VERSION" =~ ^4\.(1[8-9]|[2-9][0-9])$ ]]; then
  gha_error "Invalid desiredOCPVersion: '$REQUESTED_VERSION'. Supported values are 4.18, 4.20 and later, or 'latest'."
  exit 1
fi

echo "Resolved desiredOCPVersion: $EFFECTIVE_VERSION"
{
  echo "effective_version=$EFFECTIVE_VERSION"
  echo "crc_version_override=$CRC_VERSION_OVERRIDE"
} >>"$GITHUB_OUTPUT"
