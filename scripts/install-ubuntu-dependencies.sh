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
elif [[ "$UBUNTU_VERSION" == "20.04" ]]; then
  echo "Upgrading packages for Ubuntu 20.04"
  sudo apt-get upgrade -y
else
  echo "No specific dependencies for Ubuntu version $UBUNTU_VERSION"
fi
