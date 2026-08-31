#!/bin/bash
set -e

gha_error() {
  echo "::error::$1" >&2
  echo "[ERROR] $1" >&2
}

DESIRED_OCP_VERSION="$1"

UBUNTU_VERSION=$(lsb_release -rs)
echo "Detected Ubuntu version: $UBUNTU_VERSION"

case "$UBUNTU_VERSION" in
  22.04 | 24.04 | 26.04)
    ;;
  *)
    gha_error "Ubuntu $UBUNTU_VERSION is not supported. Supported runners: ubuntu-22.04, ubuntu-24.04, ubuntu-26.04. See https://github.com/palmsoftware/quick-ocp#supported-runners"
    exit 1
    ;;
esac

# Normalize YAML float parsing (4.2 -> 4.20)
if [[ "$DESIRED_OCP_VERSION" =~ ^4\.([0-9]+)$ ]]; then
  MINOR_VERSION="${BASH_REMATCH[1]}"
  if [ ${#MINOR_VERSION} -eq 1 ] && [ "$MINOR_VERSION" -ge 2 ]; then
    DESIRED_OCP_VERSION="4.${MINOR_VERSION}0"
    echo "Normalized version from 4.$MINOR_VERSION to $DESIRED_OCP_VERSION (YAML float parsing fix)"
  fi
fi

if [ "$UBUNTU_VERSION" = "26.04" ] && [ "$DESIRED_OCP_VERSION" != "latest" ]; then
  if [[ "$DESIRED_OCP_VERSION" =~ ^4\.([0-9]+)$ ]]; then
    MINOR="${BASH_REMATCH[1]}"
    if [ "$MINOR" -lt 22 ]; then
      gha_error "OpenShift $DESIRED_OCP_VERSION is not supported on ubuntu-26.04. Use OCP 4.22 or later, or 'latest'. Older OCP versions fail SSH during CRC start on this runner."
      exit 1
    fi
  fi
fi

echo "✓ Runner compatibility check passed"
