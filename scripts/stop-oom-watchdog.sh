#!/usr/bin/env bash
set -euo pipefail

STATE_BASE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
STATE_DIR="${CRC_OOM_WATCHDOG_STATE_DIR:-}"

if [[ -z "$STATE_DIR" ]]; then
  echo "OOM watchdog state directory is not set, nothing to stop"
  exit 0
fi

case "$STATE_DIR" in
  "$STATE_BASE"/crc-oom-watchdog.*) ;;
  *)
    echo "Refusing to clean an unexpected OOM watchdog state path: $STATE_DIR" >&2
    exit 1
    ;;
esac

if [[ ! -d "$STATE_DIR" || -L "$STATE_DIR" ]]; then
  echo "OOM watchdog state directory not found, nothing to stop"
  exit 0
fi

STATE_FILE="$STATE_DIR/watchdog"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "OOM watchdog process record not found; removing empty state directory"
  rm -rf "$STATE_DIR"
  exit 0
fi

mapfile -t WATCHDOG_STATE <"$STATE_FILE"
WATCHDOG_PID=${WATCHDOG_STATE[0]:-}
WATCHDOG_START_TIME=${WATCHDOG_STATE[1]:-}
WATCHDOG_MARKER=${WATCHDOG_STATE[2]:-}

if [[ ! "$WATCHDOG_PID" =~ ^[0-9]+$ || ! "$WATCHDOG_START_TIME" =~ ^[[:alnum:]:]+$ || ! "$WATCHDOG_MARKER" =~ ^[[:xdigit:]]{32}$ ]]; then
  echo "Invalid OOM watchdog process record; leaving state for inspection" >&2
  exit 1
fi

proc_start_time() {
  local pid=$1
  local stat rest
  local -a fields

  if [[ ! -r "/proc/$pid/stat" ]]; then
    ps -o lstart= -p "$pid" 2>/dev/null | tr -d '[:space:]'
    return "${PIPESTATUS[0]}"
  fi
  stat=$(<"/proc/$pid/stat") || return 1
  [[ "$stat" == *") "* ]] || return 1
  rest=${stat##*) }
  read -r -a fields <<<"$rest"
  [[ ${#fields[@]} -ge 20 ]] || return 1
  printf '%s\n' "${fields[19]}"
}

if ! kill -0 "$WATCHDOG_PID" 2>/dev/null; then
  echo "OOM watchdog (PID $WATCHDOG_PID) was already stopped"
  rm -rf "$STATE_DIR"
  exit 0
fi

CURRENT_START_TIME=$(proc_start_time "$WATCHDOG_PID" || true)
if [[ "$CURRENT_START_TIME" != "$WATCHDOG_START_TIME" ]]; then
  echo "OOM watchdog PID $WATCHDOG_PID has been reused; leaving the unrelated process alone"
  rm -rf "$STATE_DIR"
  exit 0
fi

if [[ -r "/proc/$WATCHDOG_PID/environ" ]]; then
  OWNED_PROCESS=$(tr '\0' '\n' <"/proc/$WATCHDOG_PID/environ" | grep -Fx "CRC_OOM_WATCHDOG_MARKER=$WATCHDOG_MARKER" || true)
else
  OWNED_PROCESS=$(ps eww -p "$WATCHDOG_PID" 2>/dev/null | grep -F "CRC_OOM_WATCHDOG_MARKER=$WATCHDOG_MARKER" || true)
fi
if [[ -z "$OWNED_PROCESS" ]]; then
  echo "OOM watchdog PID $WATCHDOG_PID does not have the expected ownership marker; leaving it alone"
  rm -rf "$STATE_DIR"
  exit 0
fi

kill "$WATCHDOG_PID" 2>/dev/null || true
for _ in {1..50}; do
  if ! kill -0 "$WATCHDOG_PID" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

if kill -0 "$WATCHDOG_PID" 2>/dev/null && [[ "$(awk '{print $3}' "/proc/$WATCHDOG_PID/stat" 2>/dev/null || true)" != "Z" ]]; then
  echo "OOM watchdog (PID $WATCHDOG_PID) did not stop; retaining its state" >&2
  exit 1
fi

echo "OOM watchdog stopped (PID $WATCHDOG_PID)"
rm -rf "$STATE_DIR"
