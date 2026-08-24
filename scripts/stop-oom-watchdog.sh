#!/bin/bash

PID_FILE="/tmp/crc-oom-watchdog.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "OOM watchdog PID file not found, nothing to stop"
  exit 0
fi

WATCHDOG_PID=$(cat "$PID_FILE")
rm -f "$PID_FILE"

if kill -0 "$WATCHDOG_PID" 2>/dev/null; then
  kill "$WATCHDOG_PID" 2>/dev/null || true
  echo "OOM watchdog stopped (PID $WATCHDOG_PID)"
else
  echo "OOM watchdog (PID $WATCHDOG_PID) was already stopped"
fi
