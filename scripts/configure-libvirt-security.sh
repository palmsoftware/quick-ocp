#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${LIBVIRT_QEMU_CONF:-/etc/libvirt/qemu.conf}"
STATE_BASE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"

if [[ "${RUNNER_ENVIRONMENT:-}" != github-hosted ]]; then
  echo "::error::The Ubuntu 26.04 CRC workaround changes the host-wide libvirt security driver and is limited to GitHub-hosted runners. On self-hosted runners, configure the OVMF/AppArmor compatibility manually after reviewing your host security policy."
  exit 1
fi

if [[ -z "${GITHUB_ENV:-}" ]]; then
  echo "GITHUB_ENV is required to register libvirt security cleanup state" >&2
  exit 1
fi

if [[ -n "${LIBVIRT_SECURITY_STATE_DIR:-}" && -f "$LIBVIRT_SECURITY_STATE_DIR/marker" ]]; then
  echo "Libvirt security workaround is already configured for this action"
  exit 0
fi

if [[ -L "$CONFIG_FILE" || (-e "$CONFIG_FILE" && ! -f "$CONFIG_FILE") ]]; then
  echo "::error::Refusing to modify non-regular libvirt configuration: $CONFIG_FILE"
  exit 1
fi

ACTIVE_SETTING_COUNT=0
if [[ -f "$CONFIG_FILE" ]]; then
  ACTIVE_SETTING_COUNT=$(grep -Ec '^[[:space:]]*security_driver[[:space:]]*=' "$CONFIG_FILE" || true)
fi
if ((ACTIVE_SETTING_COUNT > 1)); then
  echo "::error::Multiple active security_driver settings found in $CONFIG_FILE; refusing to change an ambiguous configuration"
  exit 1
fi

STATE_DIR=$(mktemp -d "$STATE_BASE/quick-ocp-libvirt-security.XXXXXX")
chmod 700 "$STATE_DIR"
MARKER_TOKEN=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
MARKER_LINE="# quick-ocp temporary libvirt security setting $MARKER_TOKEN"

CONFIG_EXISTS=false
CONFIG_MODE=644
CONFIG_OWNER=0
CONFIG_GROUP=0
if [[ -f "$CONFIG_FILE" ]]; then
  CONFIG_EXISTS=true
  if stat -c '%a' "$CONFIG_FILE" >/dev/null 2>&1; then
    CONFIG_MODE=$(stat -c '%a' "$CONFIG_FILE")
    CONFIG_OWNER=$(stat -c '%u' "$CONFIG_FILE")
    CONFIG_GROUP=$(stat -c '%g' "$CONFIG_FILE")
  else
    CONFIG_MODE=$(stat -f '%Lp' "$CONFIG_FILE")
    CONFIG_OWNER=$(stat -f '%u' "$CONFIG_FILE")
    CONFIG_GROUP=$(stat -f '%g' "$CONFIG_FILE")
  fi
  grep -E '^[[:space:]]*security_driver[[:space:]]*=' "$CONFIG_FILE" >"$STATE_DIR/original-setting" || true
else
  : >"$STATE_DIR/original-setting"
fi

UNIT_FILES=$(systemctl list-unit-files 2>/dev/null || true)
SERVICE=""
if grep -q '^libvirtd\.service' <<<"$UNIT_FILES"; then
  SERVICE=libvirtd
elif grep -q '^virtqemud\.service' <<<"$UNIT_FILES"; then
  SERVICE=virtqemud
fi

SERVICE_WAS_ACTIVE=false
if [[ -n "$SERVICE" ]] && systemctl is-active --quiet "$SERVICE"; then
  SERVICE_WAS_ACTIVE=true
fi

SOCKET=""
if grep -q '^libvirtd\.socket' <<<"$UNIT_FILES"; then
  SOCKET=libvirtd.socket
elif grep -q '^virtqemud\.socket' <<<"$UNIT_FILES"; then
  SOCKET=virtqemud.socket
fi

SOCKET_WAS_ACTIVE=false
SOCKET_WAS_ENABLED=false
if [[ -n "$SOCKET" ]]; then
  if systemctl is-active --quiet "$SOCKET"; then
    SOCKET_WAS_ACTIVE=true
  fi
  if systemctl is-enabled --quiet "$SOCKET"; then
    SOCKET_WAS_ENABLED=true
  fi
fi

printf '%s\n' "$MARKER_TOKEN" >"$STATE_DIR/marker"
printf '%s\n' "$CONFIG_EXISTS" >"$STATE_DIR/config-existed"
printf '%s\n' "$CONFIG_MODE" >"$STATE_DIR/config-mode"
printf '%s\n' "$CONFIG_OWNER" >"$STATE_DIR/config-owner"
printf '%s\n' "$CONFIG_GROUP" >"$STATE_DIR/config-group"
printf '%s\n' "$SERVICE" >"$STATE_DIR/service"
printf '%s\n' "$SERVICE_WAS_ACTIVE" >"$STATE_DIR/service-was-active"
printf '%s\n' "$SOCKET" >"$STATE_DIR/socket"
printf '%s\n' "$SOCKET_WAS_ACTIVE" >"$STATE_DIR/socket-was-active"
printf '%s\n' "$SOCKET_WAS_ENABLED" >"$STATE_DIR/socket-was-enabled"
printf '%s\n' false >"$STATE_DIR/service-touched"
printf '%s\n' false >"$STATE_DIR/socket-touched"
printf '%s\n' false >"$STATE_DIR/config-applied"
printf '%s\n' false >"$STATE_DIR/config-restored"
printf '%s\n' false >"$STATE_DIR/service-restored"
printf 'LIBVIRT_SECURITY_STATE_DIR=%s\n' "$STATE_DIR" >>"$GITHUB_ENV"

CONFIG_INPUT=/dev/null
if [[ "$CONFIG_EXISTS" == true ]]; then
  CONFIG_INPUT=$CONFIG_FILE
fi

awk -v marker="$MARKER_LINE" '
  BEGIN { replacement = "security_driver = \"none\"" }
  /^[[:space:]]*security_driver[[:space:]]*=/ {
    print marker
    print replacement
    replaced = 1
    next
  }
  { print }
  END {
    if (!replaced) {
      print marker
      print replacement
    }
  }
' "$CONFIG_INPUT" >"$STATE_DIR/config.next"

printf '%s\n' true >"$STATE_DIR/config-applied"
TEMP_CONFIG="${CONFIG_FILE}.quick-ocp-${MARKER_TOKEN}"
sudo install -o "$CONFIG_OWNER" -g "$CONFIG_GROUP" -m "$CONFIG_MODE" "$STATE_DIR/config.next" "$TEMP_CONFIG"
sudo mv -f "$TEMP_CONFIG" "$CONFIG_FILE"

if [[ -n "$SOCKET" ]]; then
  printf '%s\n' true >"$STATE_DIR/socket-touched"
  sudo systemctl enable "$SOCKET"
  sudo systemctl start "$SOCKET"
fi

if [[ -n "$SERVICE" ]]; then
  echo "Restarting $SERVICE to apply the temporary CRC security setting"
  printf '%s\n' true >"$STATE_DIR/service-touched"
  sudo systemctl restart "$SERVICE"
fi

echo "Temporarily disabled the libvirt security driver for CRC startup"
