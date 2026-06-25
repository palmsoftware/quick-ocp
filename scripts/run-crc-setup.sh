#!/bin/bash
set -e

echo "=== Environment diagnostics ==="
echo "Kernel: $(uname -r)"
echo "Ubuntu: $(lsb_release -rs 2>/dev/null || echo unknown)"
echo "Groups: $(groups)"
echo "Libvirt version: $(virsh --version 2>/dev/null || echo 'not installed')"
echo "QEMU version: $(qemu-system-x86_64 --version 2>/dev/null | head -1 || echo 'not installed')"
systemctl is-active systemd-networkd 2>/dev/null && echo "systemd-networkd: active" || echo "systemd-networkd: inactive"
systemctl is-active NetworkManager 2>/dev/null && echo "NetworkManager: active" || echo "NetworkManager: inactive"
echo "Devices:"
ls -la /dev/kvm /dev/vhost-vsock /dev/vsock 2>/dev/null || echo "  some devices missing"
echo "CRC binary: $(which crc) -> $(crc version 2>&1 | head -1)"
echo "CRC cache dir:"
ls -la ~/.crc/cache 2>/dev/null || echo "  not set up yet"
echo "Disk before setup:"
df -h / /mnt 2>/dev/null | grep -v "^Filesystem" || df -h /
echo ""

echo "=== CRC preflight check ==="
sudo -su "$USER" crc setup --check-only 2>&1 || true

# Start a background disk+process monitor during setup
echo "=== Starting background monitor ==="
(
  while true; do
    AVAIL=$(df -h / | awk 'NR==2{print $4}')
    CRC_PROCS=$(pgrep -a "crc\|xz\|zstd\|tar\|qcow" 2>/dev/null | head -5 || echo "none")
    echo "[MONITOR $(date +%H:%M:%S)] Disk avail: $AVAIL | Procs: $CRC_PROCS"
    sleep 30
  done
) &
MONITOR_PID=$!

# sudo -su re-execs with fresh group membership, which is needed for
# crc setup's "active user in libvirt group" preflight check.
echo "=== Running CRC setup (stock binary) ==="
setup_exit=0
sudo -su "$USER" crc setup --log-level debug --show-progressbars 2>&1 || setup_exit=$?

# Stop monitor
kill $MONITOR_PID 2>/dev/null || true
wait $MONITOR_PID 2>/dev/null || true

if [ $setup_exit -ne 0 ]; then
  echo "=== CRC setup FAILED (exit code $setup_exit) ==="
  echo "Disk after failed setup:"
  df -h
  echo "dmesg (last 20 lines):"
  sudo dmesg | tail -20 2>/dev/null || true
  echo "OOM kills:"
  sudo dmesg | grep -i "oom\|killed process" 2>/dev/null || echo "  none found"
  exit $setup_exit
fi

echo "=== Post-setup diagnostics ==="
echo "Libvirt networks:"
virsh --connect qemu:///system net-list --all 2>/dev/null || true
echo "Libvirt storage pools:"
virsh --connect qemu:///system pool-list --all 2>/dev/null || true
echo "Systemd CRC units:"
systemctl --user list-units 'crc-*' --no-pager 2>/dev/null || true
echo "CRC cache contents:"
ls -la ~/.crc/cache/ 2>/dev/null | head -10 || true
echo ""

# Swap in override binary after setup but before start
if [ -n "$CRC_BINARY_OVERRIDE" ] && [ -f "$CRC_BINARY_OVERRIDE" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  "$SCRIPT_DIR/install-crc-binary-override.sh" "$CRC_BINARY_OVERRIDE"

  echo "=== Preflight check with override binary ==="
  sudo -su "$USER" crc setup --check-only 2>&1 || true
fi

echo "=== Disk usage after CRC setup ==="
df -h

echo "=== Starting CRC ==="
max_attempts=3
attempt=1

while [ $attempt -le $max_attempts ]; do
  echo "=== CRC start attempt $attempt of $max_attempts ==="

  start_exit_code=0
  start_log="/tmp/crc-start-attempt-${attempt}.log"
  sudo -su "$USER" crc start --pull-secret-file pull-secret.json --log-level debug 2>&1 | tee "$start_log" || start_exit_code=$?
  start_output=$(cat "$start_log")

  if [ $start_exit_code -eq 0 ]; then
    break
  fi

  echo "=== Failure diagnostics (attempt $attempt) ==="
  echo "--- CRC status ---"
  sudo -su "$USER" crc status 2>&1 || true
  echo "--- Libvirt VMs ---"
  virsh --connect qemu:///system list --all 2>/dev/null || true
  echo "--- Libvirt networks ---"
  virsh --connect qemu:///system net-list --all 2>/dev/null || true
  echo "--- Libvirt network crc info ---"
  virsh --connect qemu:///system net-info crc 2>/dev/null || true
  virsh --connect qemu:///system net-dhcp-leases crc 2>/dev/null || true
  echo "--- NetworkManager status ---"
  nmcli device status 2>/dev/null || true
  nmcli connection show 2>/dev/null || true
  echo "--- Listening sockets ---"
  ss -tlnp 2>/dev/null | head -20 || true
  echo "--- CRC daemon journal ---"
  journalctl --user -u crc-daemon --no-pager -n 50 2>/dev/null || true
  echo "--- dmesg (last 30 lines) ---"
  sudo dmesg | tail -30 2>/dev/null || true
  echo "--- OOM kills ---"
  sudo dmesg | grep -i "oom\|killed process" 2>/dev/null || echo "  none found"
  echo ""

  if echo "$start_output" | grep -qi "failed to update kubeconfig\|cannot update kubeconfig\|Failed to connect to the CRC VM with SSH\|Unable to determine"; then
    echo "WARNING: CRC start failed with retryable error (exit code $start_exit_code)"
    if [ $attempt -lt $max_attempts ]; then
      echo "Stopping CRC and retrying..."
      sudo -su "$USER" crc stop || true
      sleep 10
      attempt=$((attempt + 1))
      continue
    fi
  fi

  echo "ERROR: CRC start failed (exit code $start_exit_code) on attempt $attempt of $max_attempts"
  exit 1
done

# Clean up pull secret immediately after use
rm -f pull-secret.json

echo "=== Disk usage after CRC start ==="
df -h
