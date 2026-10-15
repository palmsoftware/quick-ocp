#!/bin/bash
set -eo pipefail

PULL_SECRET_FILE="${PULL_SECRET_FILE:-pull-secret.json}"
if [[ ! -f "$PULL_SECRET_FILE" ]]; then
  echo "Pull secret file not found: $PULL_SECRET_FILE" >&2
  exit 1
fi

echo "=== CRC preflight check ==="
sudo -su "$USER" crc setup --check-only 2>&1 || true

echo "=== Running CRC setup ==="
# The bundle download + uncompress inside crc setup is the least reliable
# phase of deployment (mirror flakiness, partial downloads dying on
# uncompress), so retry it like the crc start loop below. Setup is
# idempotent; any nonzero exit is worth a retry.
setup_max_attempts=3
setup_attempt=1

while [ $setup_attempt -le $setup_max_attempts ]; do
  echo "=== CRC setup attempt $setup_attempt of $setup_max_attempts ==="

  setup_exit_code=0
  setup_log="/tmp/crc-setup-attempt-${setup_attempt}.log"
  sudo -su "$USER" crc setup --log-level debug --show-progressbars 2>&1 | tee "$setup_log" || setup_exit_code=$?
  if [ $setup_exit_code -eq 0 ]; then
    break
  fi

  echo "WARNING: CRC setup failed with exit code $setup_exit_code (attempt $setup_attempt of $setup_max_attempts)"
  if [ $setup_attempt -lt $setup_max_attempts ]; then
    echo "Cleaning up partial artifacts before retry..."
    # A partially downloaded or partially uncompressed bundle makes the next
    # attempt fail the same way, so remove any undersized bundle and the
    # mid-extraction directory crc leaves behind.
    for bundle in "$HOME/.crc/cache"/*.crcbundle; do
      [ -e "$bundle" ] || continue
      file_size=$(stat --format='%s' "$bundle" 2>/dev/null || stat -f '%z' "$bundle" 2>/dev/null || echo 0)
      if [ "$file_size" -lt $((1024 * 1024 * 1024)) ]; then
        echo "Removing partial bundle $(basename "$bundle") ($((file_size / 1024 / 1024))MB)"
        rm -f "$bundle"
      fi
    done
    rm -rf "$HOME/.crc/cache/tmp-extract"
    sudo -su "$USER" crc stop || true
    sleep 10
    setup_attempt=$((setup_attempt + 1))
    continue
  fi

  echo "ERROR: CRC setup failed (exit code $setup_exit_code) on attempt $setup_attempt of $setup_max_attempts"
  echo ""
  echo "=== Last 80 lines of ${setup_log} ==="
  tail -n 80 "$setup_log" || true
  echo ""
  echo "=== CRC cache contents ==="
  ls -la "$HOME/.crc/cache" 2>/dev/null || true
  echo ""
  echo "=== Disk usage ==="
  df -h || true
  echo ""
  echo "=== libvirt Logs (last 30 lines) ==="
  sudo journalctl -u "libvirtd*" --no-pager -n 30 2>/dev/null || true
  exit 1
done

echo "=== Disk usage after CRC setup ==="
df -h

echo "=== Starting CRC ==="
max_attempts=3
attempt=1

while [ $attempt -le $max_attempts ]; do
  echo "=== CRC start attempt $attempt of $max_attempts ==="

  start_exit_code=0
  start_log="/tmp/crc-start-attempt-${attempt}.log"
  sudo -su "$USER" crc start --pull-secret-file "$PULL_SECRET_FILE" --log-level debug 2>&1 | tee "$start_log" || start_exit_code=$?
  if [ $start_exit_code -eq 0 ]; then
    break
  fi

  matched_pattern=""
  for pattern in "failed to update kubeconfig:kubeconfig update" \
    "cannot update kubeconfig:kubeconfig update" \
    "Failed to connect to the CRC VM with SSH:SSH connection" \
    "Failed to update pull secret:pull secret update" \
    "connection refused:connection refused" \
    "connection reset by peer:connection reset"; do
    regex="${pattern%%:*}"
    label="${pattern#*:}"
    if grep -qi "$regex" "$start_log"; then
      matched_pattern="$label"
      break
    fi
  done

  if [ -n "$matched_pattern" ]; then
    echo "WARNING: CRC start failed with retryable error: $matched_pattern (exit code $start_exit_code)"
    if [ $attempt -lt $max_attempts ]; then
      echo "Stopping CRC and retrying..."
      sudo -su "$USER" crc stop || true
      sleep 10
      attempt=$((attempt + 1))
      continue
    fi
  fi

  echo "ERROR: CRC start failed (exit code $start_exit_code) on attempt $attempt of $max_attempts"
  echo ""
  echo "=== CRC Status ==="
  crc status 2>&1 || true
  echo ""
  echo "=== CRC Daemon Logs (last 50 lines) ==="
  sudo journalctl -u "crc*" --no-pager -n 50 2>/dev/null || true
  echo ""
  echo "=== libvirt Logs (last 30 lines) ==="
  sudo journalctl -u "libvirtd*" --no-pager -n 30 2>/dev/null || true
  exit 1
done

echo "=== Disk usage after CRC start ==="
df -h
