#!/bin/bash
# Script to patch ControllerConfig osImageURL on bootstrap node
set -e

VM="test-bootstrap"
SSH_USER="core"

echo "=== Patching ControllerConfig on bootstrap node ==="

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
            echo "ControllerConfig manifest found."
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))

        if [[ "$elapsed" -ge "$timeout" ]]; then
            echo "ERROR: Timeout waiting for ControllerConfig."
            return 1
        fi
    done
}

wait_for_mcc

# Patch the controllerconfig.yaml to use custom image
echo "Patching ControllerConfig to use custom SCOS image..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${IP}" bash <<'EOF'
CUSTOM_IMAGE="quay.io/rhn_support_fjin/scos@sha256:92de86e00311c5145eda6b4eeb4a8ea21148eec46d294d60c702ce63359942bd"
CONTROLLERCONFIG="/etc/mcc/bootstrap/machineconfigcontroller-controllerconfig.yaml"

# Backup original
sudo cp "$CONTROLLERCONFIG" "${CONTROLLERCONFIG}.backup"

# Patch baseOSContainerImage to use custom SCOS image with trustee support
sudo sed -i 's|osImageURL:.*|osImageURL: quay.io/rhn_support_fjin/scos@sha256:c6cee984d9610b70a1bd1600bf6ce798e04542227690cc24ae4b41620ac4d0e5|' /etc/mcs/bootstrap/machine-configs/* "$CONTROLLERCONFIG"

echo "ControllerConfig patched successfully"
echo "baseOSContainerImage:"
sudo grep "baseOSContainerImage:" "$CONTROLLERCONFIG"
echo "osImageURL:"
sudo grep "osImageURL:" "$CONTROLLERCONFIG"
EOF

echo "=== Patch complete ==="
