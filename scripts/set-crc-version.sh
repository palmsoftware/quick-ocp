#!/bin/bash
set -e

DESIRED_OCP_VERSION="$1"
ACTION_PATH="$2"

echo "Desired OCP Version: $DESIRED_OCP_VERSION"
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
