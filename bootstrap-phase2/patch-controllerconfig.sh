#!/bin/bash
# Script to patch ControllerConfig osImageURL on bootstrap node
set -e

VM="test-bootstrap"
SSH_USER="core"
CUSTOM_IMAGE="quay.io/rhn_support_fjin/scos@sha256:b33b351605b4df41a03c86249ab43e14e4755be7edd0cde97794da93acbfc10b"

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
               "sudo test -f /etc/mcc/bootstrap/machineconfigcontroller-controllerconfig.yaml" &>/dev/null; then
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
CONTROLLERCONFIG="/etc/mcc/bootstrap/machineconfigcontroller-controllerconfig.yaml"

# Backup original
sudo cp "$CONTROLLERCONFIG" "${CONTROLLERCONFIG}.backup"

# Patch baseOSContainerImage to use custom SCOS image with trustee support
sudo sed -i 's|baseOSContainerImage:.*|baseOSContainerImage: quay.io/rhn_support_fjin/scos@sha256:b33b351605b4df41a03c86249ab43e14e4755be7edd0cde97794da93acbfc10b|' "$CONTROLLERCONFIG"

echo "ControllerConfig patched successfully"
echo "baseOSContainerImage:"
sudo grep "baseOSContainerImage:" "$CONTROLLERCONFIG"
echo "osImageURL:"
sudo grep "osImageURL:" "$CONTROLLERCONFIG"
EOF

echo "=== Patch complete ==="
