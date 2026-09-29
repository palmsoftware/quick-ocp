#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROC_ROOT="${CRC_OOM_PROC_ROOT:-/proc}"
STATE_BASE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"

proc_start_time() {
  local proc_root=$1
  local pid=$2
  local stat rest
  local -a fields

  if [[ ! -r "$proc_root/$pid/stat" ]]; then
    [[ "$proc_root" == /proc ]] || return 1
    ps -o lstart= -p "$pid" 2>/dev/null | tr -d '[:space:]'
    return "${PIPESTATUS[0]}"
  fi
  stat=$(<"$proc_root/$pid/stat") || return 1
  [[ "$stat" == *") "* ]] || return 1
  rest=${stat##*) }
  read -r -a fields <<<"$rest"
  [[ ${#fields[@]} -ge 20 ]] || return 1
  printf '%s\n' "${fields[19]}"
}

is_crc_qemu_pid() {
  local proc_root=$1
  local pid=$2
  local process_name cmdline

  [[ -r "$proc_root/$pid/comm" && -r "$proc_root/$pid/cmdline" ]] || return 1
  process_name=$(<"$proc_root/$pid/comm")
  case "$process_name" in
    qemu-system-* | qemu-kvm | qemu-kvm-system-*) ;;
    *) return 1 ;;
  esac

  cmdline=$(tr '\0' ' ' <"$proc_root/$pid/cmdline")
  [[ "$cmdline" == *" -name guest=crc,"* || "$cmdline" == *" -name guest=crc "* || "$cmdline" == *" -name=guest=crc,"* || "$cmdline" == *" -name=guest=crc "* ]]
}

find_crc_qemu_pid() {
  local entry pid
  local -a matches=()

  for entry in "$PROC_ROOT"/[0-9]*; do
    [[ -d "$entry" ]] || continue
    pid=${entry##*/}
    if is_crc_qemu_pid "$PROC_ROOT" "$pid"; then
      matches+=("$pid")
    fi
  done

  if [[ ${#matches[@]} -ne 1 ]]; then
    echo "Expected one active CRC QEMU process; found ${#matches[@]}"
    return 1
  fi
  printf '%s\n' "${matches[0]}"
}

adjust_oom_score() {
  local proc_root=$1
  local pid=$2
  local score_file="$proc_root/$pid/oom_score_adj"

  [[ -e "$score_file" ]] || return 0
  if printf '%s\n' -500 | sudo tee "$score_file" >/dev/null; then
    echo "Adjusted oom_score_adj for CRC QEMU PID $pid"
  else
    echo "Unable to adjust oom_score_adj for CRC QEMU PID $pid" >&2
  fi
}

watchdog_loop() {
  local target_pid=${CRC_OOM_WATCHDOG_TARGET_PID:?missing CRC target PID}
  local target_start_time=${CRC_OOM_WATCHDOG_TARGET_START_TIME:?missing CRC target start time}
  local target_proc_root=${CRC_OOM_WATCHDOG_TARGET_PROC_ROOT:-/proc}
  local watchdog_interval=${CRC_OOM_WATCHDOG_INTERVAL:-15}
  local current_start_time current_score
  local sleep_pid=

  trap '[[ -z "${sleep_pid:-}" ]] || kill "$sleep_pid" 2>/dev/null || true; exit 0' TERM INT

  while true; do
    sleep "$watchdog_interval" &
    sleep_pid=$!
    wait "$sleep_pid" || true
    sleep_pid=
    current_start_time=$(proc_start_time "$target_proc_root" "$target_pid" || true)
    if [[ "$current_start_time" != "$target_start_time" ]] || ! is_crc_qemu_pid "$target_proc_root" "$target_pid"; then
      exit 0
    fi

    current_score=$(cat "$target_proc_root/$target_pid/oom_score_adj" 2>/dev/null || echo 0)
    if [[ "$current_score" =~ ^-?[0-9]+$ ]] && ((current_score > -500)); then
      adjust_oom_score "$target_proc_root" "$target_pid"
    fi
  done
}

if [[ "${1:-}" == "--watchdog" ]]; then
  watchdog_loop
  exit 0
fi

echo "=== Applying OOM protection to the CRC VM ==="
if ! CRC_QEMU_PID=$(find_crc_qemu_pid); then
  echo "$CRC_QEMU_PID"
  echo "Skipping CRC OOM protection because its QEMU process could not be identified"
  exit 0
fi

CRC_QEMU_START_TIME=$(proc_start_time "$PROC_ROOT" "$CRC_QEMU_PID" || true)
if [[ -z "$CRC_QEMU_START_TIME" ]]; then
  echo "Skipping CRC OOM protection because its process identity could not be read"
  exit 0
fi

if [[ -z "${GITHUB_ENV:-}" ]]; then
  echo "GITHUB_ENV is required to register the watchdog cleanup state" >&2
  exit 1
fi

adjust_oom_score "$PROC_ROOT" "$CRC_QEMU_PID"

STATE_DIR=$(mktemp -d "$STATE_BASE/crc-oom-watchdog.XXXXXX")
chmod 700 "$STATE_DIR"
WATCHDOG_MARKER=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')

CRC_OOM_WATCHDOG_MARKER="$WATCHDOG_MARKER" \
  CRC_OOM_WATCHDOG_TARGET_PID="$CRC_QEMU_PID" \
  CRC_OOM_WATCHDOG_TARGET_START_TIME="$CRC_QEMU_START_TIME" \
  CRC_OOM_WATCHDOG_TARGET_PROC_ROOT="$PROC_ROOT" \
  nohup bash "$SCRIPT_DIR/protect-crc-from-oom.sh" --watchdog </dev/null >/dev/null 2>&1 &
WATCHDOG_PID=$!

WATCHDOG_START_TIME=""
for _ in {1..20}; do
  WATCHDOG_START_TIME=$(proc_start_time /proc "$WATCHDOG_PID" || true)
  [[ -n "$WATCHDOG_START_TIME" ]] && break
  sleep 0.05
done

if [[ -z "$WATCHDOG_START_TIME" ]]; then
  kill "$WATCHDOG_PID" 2>/dev/null || true
  rm -rf "$STATE_DIR"
  echo "Failed to record the OOM watchdog process identity" >&2
  exit 1
fi

printf '%s\n' "$WATCHDOG_PID" "$WATCHDOG_START_TIME" "$WATCHDOG_MARKER" >"$STATE_DIR/watchdog"
printf 'CRC_OOM_WATCHDOG_STATE_DIR=%s\n' "$STATE_DIR" >>"$GITHUB_ENV"
echo "CRC OOM watchdog started (PID $WATCHDOG_PID)"
