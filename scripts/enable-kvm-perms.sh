#!/bin/bash
set -e

echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm
sudo apt-get update
sudo apt-get install -y libvirt-clients libvirt-daemon-system libvirt-daemon virtinst bridge-utils qemu-system-x86
sudo usermod -a -G kvm,libvirt $USER
if ! groups $USER | grep -q libvirt; then
  sudo adduser $(id -un) libvirt
else
  echo "User already in libvirt group"
fi
