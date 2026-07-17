#!/bin/bash
set -e

UBUNTU_VERSION=$(lsb_release -rs)
echo "Detected Ubuntu version: $UBUNTU_VERSION"

COMMON_PACKAGES=(libvirt-clients libvirt-daemon-system libvirt-daemon virtinst bridge-utils qemu-system-x86)

sudo apt-get update

if [[ "$UBUNTU_VERSION" == "22.04" ]]; then
  echo "Installing dependencies for Ubuntu 22.04"
  sudo apt-get install -y "${COMMON_PACKAGES[@]}" qemu
elif [[ "$UBUNTU_VERSION" == "24.04" ]]; then
  echo "Installing dependencies for Ubuntu 24.04"
  sudo apt-get install -y "${COMMON_PACKAGES[@]}" virtiofsd libvirt-daemon-driver-qemu
  if systemctl list-unit-files | grep -q virtqemud.socket; then
    sudo systemctl enable virtqemud.socket
    sudo systemctl start virtqemud.socket
  else
    echo "virtqemud.socket unit file does not exist. Skipping enable/start steps."
  fi
elif [[ "$UBUNTU_VERSION" == "26.04" ]]; then
  echo "Installing dependencies for Ubuntu 26.04"
  sudo apt-get install -y "${COMMON_PACKAGES[@]}" virtiofsd libvirt-daemon-driver-qemu
  if systemctl list-unit-files | grep -q libvirtd.socket; then
    sudo systemctl enable libvirtd.socket
    sudo systemctl start libvirtd.socket
  fi
  sudo modprobe vhost_vsock || true
else
  echo "Installing base dependencies for Ubuntu $UBUNTU_VERSION"
  sudo apt-get install -y "${COMMON_PACKAGES[@]}"
fi
