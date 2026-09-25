#!/bin/bash
set -euo pipefail

LOG_PATH="${CRC_MEMORY_LOG_PATH:-${RUNNER_TEMP:-/tmp}/crc-memory-pressure.log}"
PID_PATH="${CRC_MEMORY_PID_PATH:-${RUNNER_TEMP:-/tmp}/crc-memory-pressure.pid}"
INTERVAL="${CRC_MEMORY_SAMPLE_INTERVAL:-10}"
PROC_ROOT="${PROC_ROOT:-/proc}"
CGROUP_ROOT="${CGROUP_ROOT:-/sys/fs/cgroup}"

sample_memory() {
  while true; do
    printf 'timestamp=%s ' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    awk '
      /^MemTotal:/ { printf "MemTotal_kB=%s ", $2 }
      /^MemAvailable:/ { printf "MemAvailable_kB=%s ", $2 }
      /^SwapTotal:/ { printf "SwapTotal_kB=%s ", $2 }
      /^SwapFree:/ { printf "SwapFree_kB=%s ", $2 }
    ' "$PROC_ROOT/meminfo"
    awk '$1 == "pswpin" || $1 == "pswpout" { printf "%s_pages=%s ", $1, $2 }' "$PROC_ROOT/vmstat"
    if [ -r "$PROC_ROOT/pressure/memory" ]; then
      awk '{ printf "psi_%s=%s ", $1, substr($0, index($0, $2)) }' "$PROC_ROOT/pressure/memory"
    fi
    if [ -r "$CGROUP_ROOT/memory.current" ]; then
      printf 'cgroup_memory_current_bytes=%s ' "$(cat "$CGROUP_ROOT/memory.current")"
    fi
    if [ -r "$CGROUP_ROOT/memory.max" ]; then
      printf 'cgroup_memory_max_bytes=%s ' "$(cat "$CGROUP_ROOT/memory.max")"
    fi
    if [ -r "$CGROUP_ROOT/memory.events" ]; then
      awk '{ printf "cgroup_memory_%s=%s ", $1, $2 }' "$CGROUP_ROOT/memory.events"
    fi
    printf '\n'
    sleep "$INTERVAL"
  done
}

case "${1:-}" in
  start)
    if [ -f "$PID_PATH" ] && kill -0 "$(cat "$PID_PATH")" 2>/dev/null; then
      echo "Memory pressure monitor already running (PID $(cat "$PID_PATH"))"
      exit 0
    fi
    mkdir -p "$(dirname "$LOG_PATH")" "$(dirname "$PID_PATH")"
    : >"$LOG_PATH"
    script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    nohup bash "$script_path" sample >>"$LOG_PATH" 2>&1 </dev/null &
    echo "$!" >"$PID_PATH"
    echo "Started memory pressure monitor (PID $(cat "$PID_PATH")); samples every ${INTERVAL}s"
    ;;
  sample)
    sample_memory
    ;;
  stop)
    if [ -f "$PID_PATH" ]; then
      monitor_pid=$(cat "$PID_PATH")
      kill "$monitor_pid" 2>/dev/null || true
      rm -f "$PID_PATH"
    fi
    echo "=== CRC host memory pressure samples ==="
    if [ -f "$LOG_PATH" ]; then
      cat "$LOG_PATH"
    else
      echo "Memory pressure monitor did not start"
    fi
    echo "=== Kernel OOM records ==="
    if sudo journalctl -k -b --no-pager 2>/dev/null | grep -Ei 'out of memory|oom-kill|killed process'; then
      :
    else
      echo "No kernel OOM records found"
    fi
    ;;
  *)
    echo "Usage: $0 {start|stop|sample}" >&2
    exit 2
    ;;
esac
