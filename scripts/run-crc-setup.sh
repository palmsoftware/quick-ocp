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
#
# A download that hangs never exits, so a progress watchdog kills crc setup
# when ~/.crc/cache stops growing (download or tmp-extract uncompress) for
# CRC_SETUP_STALL_TIMEOUT seconds. A stall exits immediately instead of
# retrying the mirror, so the action's Quay image cache fallback takes over
# within the job budget.
setup_max_attempts=3
setup_attempt=1
CRC_CACHE_DIR="$HOME/.crc/cache"
STALL_TIMEOUT="${CRC_SETUP_STALL_TIMEOUT:-300}"
STALL_POLL="${CRC_SETUP_STALL_POLL:-15}"

cache_size_kb() {
  local size
  # Trailing slash: ~/.crc/cache is usually a symlink to /mnt/crc-cache
  # (setup-crc-cache-larger-disk.sh) and du must measure the target.
  size=$(du -sk "$CRC_CACHE_DIR/" 2>/dev/null | cut -f1) || true
  echo "${size:-0}"
}

# Signals a process and all its descendants (subshell -> sudo/tee -> crc),
# scoped to this setup run rather than matching command lines.
kill_tree() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null); do
    kill_tree "$child"
  done
  kill -TERM "$1" 2>/dev/null || true
}

# Runs crc setup under the stall watchdog. Sets setup_exit_code, and
# setup_stalled when the watchdog killed it.
run_setup_with_watchdog() {
  local log="$1" pid size last_size last_change
  setup_stalled=false
  setup_exit_code=0

  (sudo -su "$USER" crc setup --log-level debug --show-progressbars 2>&1 | tee "$log") &
  pid=$!
  last_size=$(cache_size_kb)
  last_change=$SECONDS

  while kill -0 "$pid" 2>/dev/null; do
    sleep "$STALL_POLL"
    size=$(cache_size_kb)
    if [ "$size" != "$last_size" ]; then
      last_size=$size
      last_change=$SECONDS
    elif [ $((SECONDS - last_change)) -ge "$STALL_TIMEOUT" ]; then
      setup_stalled=true
      echo "::warning::crc setup made no progress for ${STALL_TIMEOUT}s (bundle download/extract stalled) — killing it"
      kill_tree "$pid"
      break
    fi
  done

  # A setup that exits 0 while being killed still counts as success.
  wait "$pid" || setup_exit_code=$?
}

dump_setup_diagnostics() {
  local log="$1"
  echo ""
  echo "=== Last 80 lines of ${log} ==="
  tail -n 80 "$log" || true
  echo ""
  echo "=== CRC cache contents ==="
  ls -la "$CRC_CACHE_DIR" 2>/dev/null || true
  echo ""
  echo "=== Disk usage ==="
  df -h || true
  echo ""
  echo "=== libvirt Logs (last 30 lines) ==="
  sudo journalctl -u "libvirtd*" --no-pager -n 30 2>/dev/null || true
}

while [ $setup_attempt -le $setup_max_attempts ]; do
  echo "=== CRC setup attempt $setup_attempt of $setup_max_attempts ==="

  # Bundles present before this attempt (e.g. a GitHub cache hit) are
  # presumed complete; anything new after a stall is a partial download.
  preexisting_bundles=""
  for bundle in "$CRC_CACHE_DIR"/*.crcbundle; do
    if [ -e "$bundle" ]; then
      preexisting_bundles+="${bundle}"$'\n'
    fi
  done

  setup_log="/tmp/crc-setup-attempt-${setup_attempt}.log"
  run_setup_with_watchdog "$setup_log"
  if [ $setup_exit_code -eq 0 ]; then
    break
  fi

  if [ "$setup_stalled" = true ]; then
    # Remove the partial download so the Quay fallback does not mistake it
    # for a usable bundle (it skips when any .crcbundle is present).
    for bundle in "$CRC_CACHE_DIR"/*.crcbundle; do
      [ -e "$bundle" ] || continue
      if ! grep -Fxq -- "$bundle" <<<"$preexisting_bundles"; then
        echo "Removing partial bundle $(basename "$bundle") left by the stalled setup"
        rm -f "$bundle"
      fi
    done
    rm -rf "$CRC_CACHE_DIR/tmp-extract"
    echo "ERROR: CRC setup stalled on attempt $setup_attempt of $setup_max_attempts — not retrying the mirror; deferring to the image cache fallback"
    dump_setup_diagnostics "$setup_log"
    exit 1
  fi

  echo "WARNING: CRC setup failed with exit code $setup_exit_code (attempt $setup_attempt of $setup_max_attempts)"
  if [ $setup_attempt -lt $setup_max_attempts ]; then
    echo "Cleaning up partial artifacts before retry..."
    # A partially downloaded or partially uncompressed bundle makes the next
    # attempt fail the same way, so remove any undersized bundle and the
    # mid-extraction directory crc leaves behind.
    for bundle in "$CRC_CACHE_DIR"/*.crcbundle; do
      [ -e "$bundle" ] || continue
      file_size=$(stat --format='%s' "$bundle" 2>/dev/null || stat -f '%z' "$bundle" 2>/dev/null || echo 0)
      if [ "$file_size" -lt $((1024 * 1024 * 1024)) ]; then
        echo "Removing partial bundle $(basename "$bundle") ($((file_size / 1024 / 1024))MB)"
        rm -f "$bundle"
      fi
    done
    rm -rf "$CRC_CACHE_DIR/tmp-extract"
    sudo -su "$USER" crc stop || true
    sleep 10
    setup_attempt=$((setup_attempt + 1))
    continue
  fi

  echo "ERROR: CRC setup failed (exit code $setup_exit_code) on attempt $setup_attempt of $setup_max_attempts"
  dump_setup_diagnostics "$setup_log"
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

# crc start exits 0 even when it gave up waiting for cluster operators to
# settle. That line is buried in debug output, but it predicts later API
# connection resets and operator-readiness timeouts, so surface it.
if grep -q "cluster operators are still not stable" "$start_log"; then
  echo "::warning::crc start finished before cluster operators were stable; later steps may hit API connection resets or operator-readiness timeouts"
fi

echo "=== Disk usage after CRC start ==="
df -h
