#!/usr/bin/env bash
# This is to workaround a bug: https://github.com/okd-project/okd/issues/2296
set -euo pipefail

HAPROXY_VM_IP="192.168.122.112"
HAPROXY_USER="root"   # change if needed
CFG_FILE="/etc/haproxy/haproxy.cfg"

get_vm_ip() {
    local vm="$1"

    virsh domifaddr "$vm" \
        | awk '/ipv4/ {print $4}' \
        | cut -d/ -f1 \
        | head -n1
}

echo "Getting VM IPs..."

BOOTSTRAP_IP=$(get_vm_ip "test-bootstrap")
CTLPLANE_IP=$(get_vm_ip "test-ctlplane-0")

if [[ -z "$BOOTSTRAP_IP" || -z "$CTLPLANE_IP" ]]; then
    echo "ERROR: Could not retrieve VM IPs"
    exit 1
fi

echo "Bootstrap IP: $BOOTSTRAP_IP"
echo "Ctlplane IP:  $CTLPLANE_IP"

echo "Updating HAProxy config..."

ssh "${HAPROXY_USER}@${HAPROXY_VM_IP}" bash <<EOF
set -e

CFG="${CFG_FILE}"

# Backup config
cp "\$CFG" "\$CFG.bak.\$(date +%F-%H%M%S)"

# Replace IPs after hostname (preserves ports)
sed -i -E \
  -e "s/(server[[:space:]]+test-bootstrap[[:space:]]+)[0-9.]+/\\1${BOOTSTRAP_IP}/g" \
  -e "s/(server[[:space:]]+test-ctlplane-0[[:space:]]+)[0-9.]+/\\1${CTLPLANE_IP}/g" \
  "\$CFG"

# Validate config before reload
haproxy -c -f "\$CFG"

# Reload HAProxy
systemctl reload haproxy

echo "HAProxy config updated and reloaded successfully."
EOF

echo "Done."
