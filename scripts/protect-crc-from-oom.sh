#!/bin/bash
set -e

echo "=== Applying OOM protection for CRC/QEMU ==="
# Find qemu/kvm processes for the CRC VM and decrease their OOM killer score
for pid in $(pgrep -f "qemu-system-x86_64|qemu-kvm" || true); do
  if [ -w "/proc/$pid/oom_score_adj" ]; then
    # -1000 is fully immune; use -500 to reduce risk while staying fair
    echo -500 | sudo tee "/proc/$pid/oom_score_adj" || true
    echo "Adjusted oom_score_adj for PID $pid"
  fi
done
# Also protect the crc helper process if present
for pid in $(pgrep -f "^crc .*start|crc-driver" || true); do
  if [ -w "/proc/$pid/oom_score_adj" ]; then
    echo -500 | sudo tee "/proc/$pid/oom_score_adj" || true
    echo "Adjusted oom_score_adj for CRC PID $pid"
  fi
done

# Lightweight watchdog to periodically re-apply in case of restarts
(while true; do
  for pid in $(pgrep -f "qemu-system-x86_64|qemu-kvm" || true); do
    if [ -w "/proc/$pid/oom_score_adj" ]; then
      CURRENT=$(cat "/proc/$pid/oom_score_adj" || echo 0)
      if [ "$CURRENT" -gt -500 ]; then
        echo -500 | sudo tee "/proc/$pid/oom_score_adj" >/dev/null 2>&1 || true
      fi
    fi
  done
  sleep 15
done) >/dev/null 2>&1 &
