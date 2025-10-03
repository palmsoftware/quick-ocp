#!/bin/bash
set -e

groups
if ! groups $USER | grep -q libvirt; then
  sudo usermod -a -G libvirt $USER
  echo "Added user to libvirt group"
else
  echo "User already in libvirt group"
fi
groups
