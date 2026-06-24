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
echo ""

echo "=== CRC preflight check ==="
sudo -su $USER crc setup --check-only 2>&1 || true

echo "=== Running CRC setup ==="
sudo -su $USER crc setup --log-level debug --show-progressbars

echo "=== Post-setup diagnostics ==="
echo "Libvirt networks:"
virsh --connect qemu:///system net-list --all 2>/dev/null || true
echo "Libvirt storage pools:"
virsh --connect qemu:///system pool-list --all 2>/dev/null || true
echo "Systemd CRC units:"
systemctl --user list-units 'crc-*' --no-pager 2>/dev/null || true
echo ""

echo "=== Disk usage after CRC setup ==="
df -h

echo "=== Starting CRC ==="
max_attempts=3
attempt=1

while [ $attempt -le $max_attempts ]; do
  echo "=== CRC start attempt $attempt of $max_attempts ==="

  start_exit_code=0
  start_log="/tmp/crc-start-attempt-${attempt}.log"
  sudo -su $USER crc start --pull-secret-file pull-secret.json --log-level debug 2>&1 | tee "$start_log" || start_exit_code=$?
  start_output=$(cat "$start_log")

  if [ $start_exit_code -eq 0 ]; then
    break
  fi

  echo "=== Failure diagnostics (attempt $attempt) ==="
  echo "--- CRC status ---"
  crc status 2>&1 || true
  echo "--- Libvirt VMs ---"
  virsh --connect qemu:///system list --all 2>/dev/null || true
  echo "--- Listening sockets ---"
  ss -tlnp 2>/dev/null | head -20 || true
  echo "--- CRC daemon journal ---"
  journalctl --user -u crc-daemon --no-pager -n 50 2>/dev/null || true
  echo "--- dmesg (last 30 lines) ---"
  dmesg | tail -30 2>/dev/null || true
  echo ""

  if echo "$start_output" | grep -qi "failed to update kubeconfig\|cannot update kubeconfig\|Failed to connect to the CRC VM with SSH"; then
    echo "WARNING: CRC start failed with retryable error (exit code $start_exit_code)"
    if [ $attempt -lt $max_attempts ]; then
      echo "Stopping CRC and retrying..."
      sudo -su $USER crc stop || true
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
