#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${LIBVIRT_QEMU_CONF:-/etc/libvirt/qemu.conf}"
STATE_BASE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
STATE_DIR="${LIBVIRT_SECURITY_STATE_DIR:-}"

if [[ -z "$STATE_DIR" ]]; then
  echo "Libvirt security state is not set, nothing to restore"
  exit 0
fi

case "$STATE_DIR" in
  "$STATE_BASE"/quick-ocp-libvirt-security.*) ;;
  *)
    echo "Refusing to clean an unexpected libvirt security state path: $STATE_DIR" >&2
    exit 1
    ;;
esac

if [[ ! -d "$STATE_DIR" || -L "$STATE_DIR" ]]; then
  echo "Libvirt security state directory not found, nothing to restore"
  exit 0
fi

required_files=(marker config-existed config-mode config-owner config-group service service-was-active socket socket-was-active socket-was-enabled service-touched socket-touched config-applied config-restored service-restored original-setting)
for file in "${required_files[@]}"; do
  if [[ ! -f "$STATE_DIR/$file" ]]; then
    echo "Incomplete libvirt security state in $STATE_DIR; leaving it for inspection" >&2
    exit 1
  fi
done

MARKER_TOKEN=$(<"$STATE_DIR/marker")
CONFIG_EXISTS=$(<"$STATE_DIR/config-existed")
CONFIG_MODE=$(<"$STATE_DIR/config-mode")
CONFIG_OWNER=$(<"$STATE_DIR/config-owner")
CONFIG_GROUP=$(<"$STATE_DIR/config-group")
SERVICE=$(<"$STATE_DIR/service")
SERVICE_WAS_ACTIVE=$(<"$STATE_DIR/service-was-active")
SOCKET=$(<"$STATE_DIR/socket")
SOCKET_WAS_ACTIVE=$(<"$STATE_DIR/socket-was-active")
SOCKET_WAS_ENABLED=$(<"$STATE_DIR/socket-was-enabled")
SERVICE_TOUCHED=$(<"$STATE_DIR/service-touched")
SOCKET_TOUCHED=$(<"$STATE_DIR/socket-touched")
CONFIG_APPLIED=$(<"$STATE_DIR/config-applied")
CONFIG_RESTORED=$(<"$STATE_DIR/config-restored")
SERVICE_RESTORED=$(<"$STATE_DIR/service-restored")

if [[ ! "$MARKER_TOKEN" =~ ^[[:xdigit:]]{32}$ || ! "$CONFIG_MODE" =~ ^[0-7]{3,4}$ || ! "$CONFIG_OWNER" =~ ^[0-9]+$ || ! "$CONFIG_GROUP" =~ ^[0-9]+$ ]]; then
  echo "Invalid libvirt security state in $STATE_DIR; leaving it for inspection" >&2
  exit 1
fi
if [[ "$CONFIG_EXISTS" != true && "$CONFIG_EXISTS" != false || "$CONFIG_APPLIED" != true && "$CONFIG_APPLIED" != false || "$CONFIG_RESTORED" != true && "$CONFIG_RESTORED" != false || "$SERVICE_WAS_ACTIVE" != true && "$SERVICE_WAS_ACTIVE" != false || "$SERVICE_RESTORED" != true && "$SERVICE_RESTORED" != false || "$SOCKET_WAS_ACTIVE" != true && "$SOCKET_WAS_ACTIVE" != false || "$SOCKET_WAS_ENABLED" != true && "$SOCKET_WAS_ENABLED" != false || "$SERVICE_TOUCHED" != true && "$SERVICE_TOUCHED" != false || "$SOCKET_TOUCHED" != true && "$SOCKET_TOUCHED" != false ]]; then
  echo "Invalid libvirt security state flags in $STATE_DIR; leaving it for inspection" >&2
  exit 1
fi
case "$SERVICE" in
  "" | libvirtd | virtqemud) ;;
  *)
    echo "Invalid libvirt service in $STATE_DIR; leaving it for inspection" >&2
    exit 1
    ;;
esac
case "$SOCKET" in
  "" | libvirtd.socket | virtqemud.socket) ;;
  *)
    echo "Invalid libvirt socket in $STATE_DIR; leaving it for inspection" >&2
    exit 1
    ;;
esac

MARKER_LINE="# quick-ocp temporary libvirt security setting $MARKER_TOKEN"
TEMP_CONFIG="${CONFIG_FILE}.quick-ocp-${MARKER_TOKEN}"
sudo rm -f "$TEMP_CONFIG"

if [[ "$CONFIG_APPLIED" == true && "$CONFIG_RESTORED" != true ]]; then
  MARKER_COUNT=0
  if [[ -f "$CONFIG_FILE" ]]; then
    MARKER_COUNT=$(grep -Fxc "$MARKER_LINE" "$CONFIG_FILE" || true)
  fi

  if ((MARKER_COUNT > 1)); then
    echo "Multiple temporary libvirt security markers found; retaining state in $STATE_DIR" >&2
    exit 1
  elif ((MARKER_COUNT == 0)); then
    echo "Temporary libvirt setting is already absent; leaving qemu.conf unchanged"
  else
    HAD_ORIGINAL=false
    if [[ -s "$STATE_DIR/original-setting" ]]; then
      HAD_ORIGINAL=true
    fi
    if ! awk -v marker="$MARKER_LINE" -v had_original="$HAD_ORIGINAL" -v original_file="$STATE_DIR/original-setting" '
      BEGIN {
        if (had_original == "true" && (getline original < original_file) <= 0) exit 2
        close(original_file)
      }
      $0 == marker {
        if (getline current > 0) {
          if (had_original == "true") print original
          else if (current != "security_driver = \"none\"") print current
        }
        next
      }
      { print }
    ' "$CONFIG_FILE" >"$STATE_DIR/config.restored"; then
      echo "Unable to prepare the restored libvirt configuration; retaining state in $STATE_DIR" >&2
      exit 1
    fi

    if [[ "$CONFIG_EXISTS" == false && ! -s "$STATE_DIR/config.restored" ]]; then
      sudo rm -f "$CONFIG_FILE"
    else
      sudo install -o "$CONFIG_OWNER" -g "$CONFIG_GROUP" -m "$CONFIG_MODE" "$STATE_DIR/config.restored" "$TEMP_CONFIG"
      sudo mv -f "$TEMP_CONFIG" "$CONFIG_FILE"
    fi
  fi
  printf '%s\n' true >"$STATE_DIR/config-restored"
fi

if [[ "$SERVICE_TOUCHED" == true && "$SERVICE_RESTORED" != true && -n "$SERVICE" ]]; then
  if [[ "$SERVICE_WAS_ACTIVE" == true ]]; then
    if systemctl is-active --quiet "$SERVICE"; then
      sudo systemctl restart "$SERVICE"
    else
      sudo systemctl start "$SERVICE"
    fi
  elif systemctl is-active --quiet "$SERVICE"; then
    sudo systemctl stop "$SERVICE"
  fi
  printf '%s\n' true >"$STATE_DIR/service-restored"
fi

if [[ "$SOCKET_TOUCHED" == true && -n "$SOCKET" ]]; then
  if [[ "$SOCKET_WAS_ACTIVE" == true ]]; then
    if ! systemctl is-active --quiet "$SOCKET"; then
      sudo systemctl start "$SOCKET"
    fi
  elif systemctl is-active --quiet "$SOCKET"; then
    sudo systemctl stop "$SOCKET"
  fi

  if [[ "$SOCKET_WAS_ENABLED" == true ]]; then
    if ! systemctl is-enabled --quiet "$SOCKET"; then
      sudo systemctl enable "$SOCKET"
    fi
  elif systemctl is-enabled --quiet "$SOCKET"; then
    sudo systemctl disable "$SOCKET"
  fi
fi

echo "Libvirt security configuration and service state restored"
rm -rf "$STATE_DIR"
