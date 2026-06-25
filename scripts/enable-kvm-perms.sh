#!/bin/bash
set -e

echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
echo 'KERNEL=="vhost-vsock", GROUP="kvm", MODE="0666"' | sudo tee -a /etc/udev/rules.d/99-kvm4all.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm
sudo udevadm trigger --name-match=vhost-vsock 2>/dev/null || true
sudo chmod 0666 /dev/kvm 2>/dev/null || true
sudo chmod 0666 /dev/vhost-vsock 2>/dev/null || true
sudo apt-get install -y libvirt-clients libvirt-daemon-system libvirt-daemon virtinst bridge-utils qemu-system-x86
sudo usermod -a -G kvm,libvirt $USER
if ! groups $USER | grep -q libvirt; then
  sudo adduser $(id -un) libvirt
else
  echo "User already in libvirt group"
fi

# Kernel 7.0 added network namespace support to AF_VSOCK. If child_ns_mode
# is set to "local", vsock connections from outside a namespace get
# "connection reset by peer" — which breaks CRC's gvisor-tap-vsock SSH tunnel.
# Force global mode before any child namespaces are created (write-once sysctl).
if [ -f /proc/sys/net/vsock/child_ns_mode ]; then
  CURRENT_MODE=$(cat /proc/sys/net/vsock/child_ns_mode)
  echo "=== vsock namespace mode: child_ns_mode=$CURRENT_MODE ==="
  if [ "$CURRENT_MODE" != "global" ]; then
    echo "Setting child_ns_mode to global for CRC vsock compatibility"
    echo global | sudo tee /proc/sys/net/vsock/child_ns_mode || echo "WARNING: Failed to set child_ns_mode (may already be locked)"
  fi
  echo "ns_mode=$(cat /proc/sys/net/vsock/ns_mode 2>/dev/null || echo 'N/A')"
else
  echo "=== vsock namespace sysctls not present (kernel < 7.0) ==="
fi

echo "=== KVM permissions check ==="
ls -la /dev/kvm /dev/vhost-vsock 2>/dev/null || true
id
