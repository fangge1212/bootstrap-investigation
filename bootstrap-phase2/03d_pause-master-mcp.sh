#!/bin/bash
# Script to pause master MachineConfigPool on bootstrap node
set -e

VM="test-bootstrap"
SSH_USER="core"

echo "=== Pausing master MachineConfigPool on bootstrap node ==="

# Get the IP address from virsh domifaddr
IP=$(virsh domifaddr "$VM" | awk '/ipv4/ {split($4,a,"/"); print a[1]}')

if [[ -z "$IP" ]]; then
    echo "Error: Could not get IP for VM $VM"
    exit 1
fi

echo "VM $VM IP: $IP"

# The actual wait for file will be done inside the ssh session below

# Patch the master MachineConfigPool to set spec.paused to true
echo "Patching master MachineConfigPool to set spec.paused: true..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${IP}" bash <<'EOF'
MCP_FILE="/etc/mcs/bootstrap/machine-pools/master.yaml"

# Wait for the file to appear
echo "Waiting for MachineConfigPool file to appear..."
INTERVAL=2

while ! sudo test -f "$MCP_FILE"; do
    sleep $INTERVAL
done

echo "MachineConfigPool file found: $MCP_FILE"

# Check if spec.paused already exists
if sudo grep -q "paused:" "$MCP_FILE"; then
    echo "paused field already exists, updating value..."
    sudo sed -i 's/paused:.*/paused: true/' "$MCP_FILE"
else
    echo "Adding paused: true to spec..."
    # Add paused: true after the spec: line
    sudo sed -i '/^spec:/a\  paused: true' "$MCP_FILE"
fi

echo "MachineConfigPool patched successfully"

echo ""
echo "Verification - MachineConfigPool spec.paused:"
sudo grep  "paused" "$MCP_FILE"
EOF

echo ""
echo "=== Patch complete ==="
