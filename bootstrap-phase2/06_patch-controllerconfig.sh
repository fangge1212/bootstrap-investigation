#!/bin/bash
# Script to patch MachineConfig and ControllerConfig osImageURL on bootstrap node
set -e

VM="test-bootstrap"
SSH_USER="core"

echo "=== Patching MachineConfig and ControllerConfig on bootstrap node ==="

# Get the IP address from virsh domifaddr
IP=$(virsh domifaddr "$VM" | awk '/ipv4/ {split($4,a,"/"); print a[1]}')

if [[ -z "$IP" ]]; then
    echo "Error: Could not get IP for VM $VM"
    exit 1
fi

echo "VM $VM IP: $IP"

# Wait for MCC to be available
wait_for_mcc() {
    local timeout=600
    local interval=5
    local elapsed=0

    echo "Waiting for Machine Config Controller to be ready..."

    while true; do
        if ssh -o ConnectTimeout=3 \
               -o BatchMode=yes \
               -o StrictHostKeyChecking=no \
               "${SSH_USER}@${IP}" \
               "sudo test -d /etc/mcs/bootstrap/machine-configs/" &>/dev/null; then
            echo "MachineConfig manifest found."
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))

        if [[ "$elapsed" -ge "$timeout" ]]; then
            echo "ERROR: Timeout waiting for MachineConfig."
            return 1
        fi
    done
}

wait_for_mcc

# Patch the machine and controller config yaml to use custom image
echo "Patching MachineConfig and ControllerConfig to use custom SCOS image..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${IP}" bash <<'EOF'
MACHINECONFIG=/etc/mcs/bootstrap/machine-configs/
CONTROLLERCONFIG="/etc/mcc/bootstrap/machineconfigcontroller-controllerconfig.yaml"

# Patch osImageURL and baseOSContainerImage to use custom SCOS image with trustee support
sudo sed -i 's|osImageURL:.*|osImageURL: quay.io/rhn_support_fjin/scos@sha256:c6cee984d9610b70a1bd1600bf6ce798e04542227690cc24ae4b41620ac4d0e5|' /etc/mcs/bootstrap/machine-configs/*
echo "MachineConfig osImageURL patched successfully"
sudo sed -i 's|osImageURL:.*|osImageURL: quay.io/rhn_support_fjin/scos@sha256:c6cee984d9610b70a1bd1600bf6ce798e04542227690cc24ae4b41620ac4d0e5|' /etc/mcc/bootstrap/machineconfigcontroller-controllerconfig.yaml
sudo sed -i 's|baseOSContainerImage:.*|baseOSContainerImage: quay.io/rhn_support_fjin/scos@sha256:c6cee984d9610b70a1bd1600bf6ce798e04542227690cc24ae4b41620ac4d0e5|' /etc/mcc/bootstrap/machineconfigcontroller-controllerconfig.yaml
echo "ControllerConfig patched successfully"

echo "Verification:"
sudo grep "osImageURL:" "$CONTROLLERCONFIG" -irn
sudo grep "baseOSContainerImage:" "$CONTROLLERCONFIG" -irn
EOF

echo "=== Patch complete ==="
