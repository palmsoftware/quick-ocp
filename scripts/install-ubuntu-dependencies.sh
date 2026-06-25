#!/bin/bash
set -e

UBUNTU_VERSION=$(lsb_release -rs)
echo "Detected Ubuntu version: $UBUNTU_VERSION"
if [[ "$UBUNTU_VERSION" == "22.04" ]]; then
  echo "Installing specific dependencies for Ubuntu 22.04"
  sudo apt-get update
  sudo apt-get install -y qemu
elif [[ "$UBUNTU_VERSION" == "24.04" ]]; then
  echo "Installing specific dependencies for Ubuntu 24.04"
  sudo apt-get update
  sudo apt-get install -y virtiofsd libvirt-daemon-system libvirt-daemon-driver-qemu
  if systemctl list-unit-files | grep -q virtqemud.socket; then
    sudo systemctl enable virtqemud.socket
    sudo systemctl start virtqemud.socket
  else
    echo "virtqemud.socket unit file does not exist. Skipping enable/start steps."
  fi
elif [[ "$UBUNTU_VERSION" == "26.04" ]]; then
  echo "Installing specific dependencies for Ubuntu 26.04"
  sudo apt-get update
  sudo apt-get install -y virtiofsd libvirt-daemon-system libvirt-daemon-driver-qemu qemu-system-x86
  if systemctl list-unit-files | grep -q libvirtd.socket; then
    sudo systemctl enable libvirtd.socket
    sudo systemctl start libvirtd.socket
  fi
  sudo modprobe vhost_vsock || true
  # Switch to NetworkManager for CRC system networking mode
  # (vsock/user mode is broken on kernel 7.0)
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  "$SCRIPT_DIR/switch-to-networkmanager.sh"
else
  echo "No specific dependencies for Ubuntu version $UBUNTU_VERSION"
fi
