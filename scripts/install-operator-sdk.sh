#!/usr/bin/env bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# Defaults (override with env or flags)
: "${OPERATOR_SDK_VERSION:=v1.34.2}"
: "${BIN_DIR:=/usr/local/bin}"
FORCE_INSTALL=false

usage() {
  cat <<EOF
Install operator-sdk locally

USAGE:
  $(basename "$0") [--version vX.Y.Z] [--bin-dir PATH] [--force] [--help]

OPTIONS:
  --version vX.Y.Z   Operator SDK version tag to install (default: ${OPERATOR_SDK_VERSION})
  --bin-dir PATH     Directory to install the binary (default: ${BIN_DIR})
  --force            Reinstall even if operator-sdk is already present in PATH
  --help             Show this help message

NOTES:
  - This script resolves OS/arch and downloads the matching release asset from GitHub
  - Requires curl
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || { err "--version requires a value"; exit 1; }
        OPERATOR_SDK_VERSION="$2"; shift 2 ;;
      --bin-dir)
        [[ $# -ge 2 ]] || { err "--bin-dir requires a value"; exit 1; }
        BIN_DIR="$2"; shift 2 ;;
      --force)
        FORCE_INSTALL=true; shift ;;
      --help|-h)
        usage; exit 0 ;;
      *)
        err "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
}

require_prereqs() {
  if ! command -v curl >/dev/null 2>&1; then
    err "curl is required"
    exit 1
  fi
}

already_installed() {
  if command -v operator-sdk >/dev/null 2>&1; then
    ok "operator-sdk already present: $(operator-sdk version 2>/dev/null || echo present)"
    return 0
  fi
  return 1
}

resolve_os_arch() {
  local os arch mapped_arch
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) mapped_arch=amd64 ;;
    aarch64|arm64) mapped_arch=arm64 ;;
    *) err "Unsupported architecture: $arch"; exit 1 ;;
  esac
  case "$os" in
    linux|darwin) : ;; 
    *) err "Unsupported OS: $os"; exit 1 ;;
  esac
  OS_ARCH="${os}_${mapped_arch}"
}

install_operator_sdk() {
  resolve_os_arch
  local url="https://github.com/operator-framework/operator-sdk/releases/download/${OPERATOR_SDK_VERSION}/operator-sdk_${OS_ARCH}"
  info "Downloading operator-sdk ${OPERATOR_SDK_VERSION} for ${OS_ARCH}"
  local tmpfile
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT
  if ! curl -fsSL -o "$tmpfile" "$url"; then
    err "Failed to download: $url"
    exit 1
  fi

  chmod +x "$tmpfile"
  mkdir -p "$BIN_DIR"

  if mv "$tmpfile" "${BIN_DIR}/operator-sdk" 2>/dev/null; then
    :
  else
    info "Escalating privileges to install into ${BIN_DIR}"
    sudo mv "$tmpfile" "${BIN_DIR}/operator-sdk"
  fi

  ok "operator-sdk installed to ${BIN_DIR}/operator-sdk"
}

verify() {
  if command -v operator-sdk >/dev/null 2>&1; then
    info "operator-sdk version: $(operator-sdk version 2>/dev/null | tr -d '\n')"
  else
    err "operator-sdk not found after installation"
    exit 1
  fi
}

main() {
  parse_args "$@"
  require_prereqs
  if ! $FORCE_INSTALL && already_installed; then
    return 0
  fi
  install_operator_sdk
  verify
}

main "$@"


