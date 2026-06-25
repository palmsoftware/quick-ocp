#!/bin/bash
set -e

echo "=== Switching from systemd-networkd to NetworkManager ==="

verify_connectivity() {
  local label="$1"
  echo "--- Verifying connectivity ($label) ---"
  if curl -sf --connect-timeout 10 https://mirror.openshift.com/ >/dev/null 2>&1; then
    echo "Connectivity OK"
    return 0
  else
    echo "ERROR: Connectivity check failed ($label)"
    return 1
  fi
}

verify_connectivity "before switch"

echo "--- Installing NetworkManager ---"
sudo apt-get install -y network-manager

echo "--- Discovering active network config ---"
# Find the primary interface (the one with a default route)
PRIMARY_IF=$(ip route show default | awk '{print $5}' | head -1)
echo "Primary interface: $PRIMARY_IF"
ip addr show "$PRIMARY_IF"

echo "--- Configuring NetworkManager to manage $PRIMARY_IF ---"
# Ensure NetworkManager manages all devices (not just wifi)
sudo tee /etc/NetworkManager/conf.d/10-manage-all.conf >/dev/null <<EOF
[main]
plugins=keyfile

[keyfile]
unmanaged-devices=none

[device]
wifi.scan-rand-mac-address=no
EOF

# Tell NetworkManager not to touch DNS (let systemd-resolved handle it)
sudo tee /etc/NetworkManager/conf.d/20-dns.conf >/dev/null <<EOF
[main]
dns=systemd-resolved
EOF

echo "--- Starting NetworkManager ---"
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager
sleep 2

echo "--- NetworkManager status ---"
nmcli general status || true
nmcli device status || true

echo "--- Stopping systemd-networkd ---"
sudo systemctl stop systemd-networkd
sudo systemctl disable systemd-networkd
sleep 2

echo "--- Letting NetworkManager pick up the interface ---"
# If NM didn't auto-configure, create a connection manually
if ! nmcli -t -f DEVICE,STATE device | grep -q "$PRIMARY_IF:connected"; then
  echo "NetworkManager hasn't connected $PRIMARY_IF, creating connection..."
  sudo nmcli connection add type ethernet ifname "$PRIMARY_IF" con-name "runner-eth" \
    ipv4.method auto ipv6.method auto
  sudo nmcli connection up "runner-eth"
  sleep 3
fi

echo "--- Post-switch network state ---"
nmcli device status
ip addr show "$PRIMARY_IF"
ip route show default

verify_connectivity "after switch"

echo "--- Verifying systemd-networkd is stopped ---"
if systemctl is-active --quiet systemd-networkd; then
  echo "ERROR: systemd-networkd is still running"
  exit 1
fi
echo "systemd-networkd is stopped"

echo "=== NetworkManager switch complete ==="
