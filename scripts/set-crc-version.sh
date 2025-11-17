#!/bin/bash
set -e

DESIRED_OCP_VERSION="$1"
ACTION_PATH="$2"
EXPLICIT_CRC_VERSION="${3:-}"

# Normalize version string to handle YAML float parsing issues
# YAML parses 4.20 as 4.2, so we need to normalize it back
if [[ "$DESIRED_OCP_VERSION" =~ ^4\.([0-9]+)$ ]]; then
  MINOR_VERSION="${BASH_REMATCH[1]}"
  # If minor version is a single digit >= 2, assume it's missing a trailing zero
  # (e.g., 4.2 should be 4.20, but 4.18, 4.19 are already correct)
  if [ ${#MINOR_VERSION} -eq 1 ] && [ "$MINOR_VERSION" -ge 2 ]; then
    DESIRED_OCP_VERSION="4.${MINOR_VERSION}0"
    echo "Normalized version from 4.$MINOR_VERSION to $DESIRED_OCP_VERSION (YAML float parsing fix)"
  fi
fi

echo "Desired OCP Version: $DESIRED_OCP_VERSION"

# If an explicit CRC version is provided, use it directly
if [ -n "$EXPLICIT_CRC_VERSION" ]; then
  echo "✓ Using explicitly specified CRC version: $EXPLICIT_CRC_VERSION"
  echo "crc_version=$EXPLICIT_CRC_VERSION" | tee "$GITHUB_OUTPUT"
  exit 0
fi

# Check if there's a pinned version (even for 'latest')
VERSION_PINS_FILE="$ACTION_PATH/crc-version-pins.json"
if [ -f "$VERSION_PINS_FILE" ]; then
  echo "Checking version pins file..."
  PINNED_VERSION=$(jq -r --arg ocp "$DESIRED_OCP_VERSION" '.version_pins[$ocp] // "auto"' "$VERSION_PINS_FILE")

  if [ "$PINNED_VERSION" != "auto" ] && [ "$PINNED_VERSION" != "null" ]; then
    echo "✓ Found pinned CRC version for OCP $DESIRED_OCP_VERSION: $PINNED_VERSION"

    # Check if there's a known issue documented
    KNOWN_ISSUE=$(jq -r --arg ocp "$DESIRED_OCP_VERSION" '.known_issues[$ocp].issue // empty' "$VERSION_PINS_FILE")
    if [ -n "$KNOWN_ISSUE" ]; then
      echo "  ℹ This version is pinned due to known issues. See: $KNOWN_ISSUE"
    fi

    CRC_VERSION="$PINNED_VERSION"
    echo "crc_version=$CRC_VERSION" | tee "$GITHUB_OUTPUT"
    exit 0
  else
    echo "No pinned version found for OCP $DESIRED_OCP_VERSION, using default behavior..."
  fi
else
  echo "Version pins file not found at $VERSION_PINS_FILE, using default behavior..."
fi

if [ "$DESIRED_OCP_VERSION" = "latest" ]; then
  echo "crc_version=latest" | tee "$GITHUB_OUTPUT"
else
  # Only allow OCP versions 4.18 and above
  if [[ ! "$DESIRED_OCP_VERSION" =~ ^4\.(1[8-9]|[2-9][0-9])$ ]] && [[ "$DESIRED_OCP_VERSION" != "latest" ]]; then
    echo "[ERROR] Only OpenShift versions 4.18 and above are supported in this action." >&2
    exit 1
  fi

  echo "Fetching CRC version for OCP $DESIRED_OCP_VERSION..."
  CRC_VERSION=$("$ACTION_PATH/scripts/fetch-ocp-crc-version.sh" "$DESIRED_OCP_VERSION")
  echo "Script returned: $CRC_VERSION"
  if [[ $CRC_VERSION == No* ]] || [[ $CRC_VERSION == Error* ]]; then
    echo "[ERROR] The requested OpenShift version ($DESIRED_OCP_VERSION) is not supported or no matching CRC release was found." >&2
    echo "Details: $CRC_VERSION" >&2
    echo "Please choose a supported OCP version (e.g., 4.18 or above) or check https://github.com/crc-org/crc/releases for available versions." >&2
    exit 1
  fi
  # If script returns 'latest' due to API issues, use latest
  if [[ $CRC_VERSION == "latest" ]]; then
    echo "Using latest CRC version due to API fallback"
  fi
  echo "crc_version=$CRC_VERSION" | tee "$GITHUB_OUTPUT"
fi
