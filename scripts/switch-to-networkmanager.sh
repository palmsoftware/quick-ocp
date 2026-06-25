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
    echo "WARNING: Connectivity check failed ($label)"
    return 1
  fi
}

verify_connectivity "before switch"

echo "--- Installing NetworkManager ---"
sudo apt-get install -y network-manager

# Capture current network config before stopping networkd
PRIMARY_IF=$(ip route show default | awk '{print $5}' | head -1)
PRIMARY_IP=$(ip -4 addr show "$PRIMARY_IF" | grep -oP 'inet \K[\d.]+/\d+')
PRIMARY_GW=$(ip route show default | awk '{print $3}' | head -1)
PRIMARY_DNS=$(grep nameserver /etc/resolv.conf | head -1 | awk '{print $2}')

echo "--- Current network config ---"
echo "Interface: $PRIMARY_IF"
echo "IP: $PRIMARY_IP"
echo "Gateway: $PRIMARY_GW"
echo "DNS: $PRIMARY_DNS"

echo "--- Configuring NetworkManager ---"
sudo tee /etc/NetworkManager/conf.d/10-manage-all.conf >/dev/null <<EOF
[main]
plugins=keyfile
dns=systemd-resolved

[keyfile]
unmanaged-devices=none
EOF

# Pre-create the connection profile with static IP (matching current config)
# so NM can bring it up immediately after networkd stops
sudo nmcli connection add type ethernet ifname "$PRIMARY_IF" con-name "runner-eth" \
  ipv4.addresses "$PRIMARY_IP" \
  ipv4.gateway "$PRIMARY_GW" \
  ipv4.dns "$PRIMARY_DNS" \
  ipv4.method manual \
  connection.autoconnect yes 2>&1 || true

echo "--- Stopping and masking systemd-networkd ---"
# Must stop sockets AND mask the service to prevent socket activation from restarting it.
# CRC's preflight check uses 'systemctl status systemd-networkd.service' and rejects it.
sudo systemctl stop systemd-networkd.socket systemd-networkd-varlink.socket systemd-networkd-resolve-hook.socket 2>/dev/null || true
sudo systemctl disable systemd-networkd.socket systemd-networkd-varlink.socket systemd-networkd-resolve-hook.socket 2>/dev/null || true
sudo systemctl stop systemd-networkd
sudo systemctl disable systemd-networkd 2>/dev/null || true
sudo systemctl mask systemd-networkd 2>/dev/null || true

echo "--- Restarting NetworkManager to pick up devices ---"
sudo systemctl restart NetworkManager
sleep 3

echo "--- NetworkManager status ---"
nmcli general status || true
nmcli device status || true
nmcli connection show || true

# Bring up the connection if not already
if ! nmcli -t -f DEVICE,STATE device | grep -q "$PRIMARY_IF:connected"; then
  echo "--- Activating runner-eth connection ---"
  sudo nmcli connection up "runner-eth" 2>&1 || true
  sleep 3
fi

echo "--- Post-switch network state ---"
nmcli device status || true
ip addr show "$PRIMARY_IF"
ip route show default

verify_connectivity "after switch" || {
  echo "=== FALLBACK: Connectivity lost, trying DHCP instead of static ==="
  sudo nmcli connection modify "runner-eth" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns ""
  sudo nmcli connection up "runner-eth" 2>&1 || true
  sleep 5
  verify_connectivity "after DHCP fallback" || {
    echo "ERROR: Cannot restore connectivity"
    exit 1
  }
}

# Wait for NM to fully stabilize — CRC needs NM fully managing the interface
echo "--- Waiting for NetworkManager to fully connect ---"
for i in $(seq 1 30); do
  NM_STATE=$(nmcli -t -f STATE general 2>/dev/null || echo "unknown")
  if [ "$NM_STATE" = "connected" ]; then
    echo "NetworkManager state: connected"
    break
  fi
  echo "NetworkManager state: $NM_STATE (waiting...)"
  sleep 2
done

echo "--- Verifying systemd-networkd is stopped ---"
if systemctl is-active --quiet systemd-networkd; then
  echo "WARNING: systemd-networkd is still running"
else
  echo "systemd-networkd is stopped"
fi

echo "=== NetworkManager switch complete ==="
