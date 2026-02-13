#!/bin/bash
# Script to patch bootkube ControllerConfig manifest on bootstrap node
set -e

VM="test-bootstrap"
SSH_USER="core"
CUSTOM_OSIMAGE="quay.io/rhn_support_fjin/scos@sha256:c6cee984d9610b70a1bd1600bf6ce798e04542227690cc24ae4b41620ac4d0e5"

echo "=== Patching bootkube ControllerConfig manifest on bootstrap node ==="

# Get the IP address from virsh domifaddr
IP=$(virsh domifaddr "$VM" | awk '/ipv4/ {split($4,a,"/"); print a[1]}')

if [[ -z "$IP" ]]; then
    echo "Error: Could not get IP for VM $VM"
    exit 1
fi

echo "VM $VM IP: $IP"

# Wait for bootkube manifest to be generated
wait_for_manifest() {
    local interval=2

    echo "Waiting for bootkube ControllerConfig manifest..."

    while true; do
        if ssh -o ConnectTimeout=3 \
               -o BatchMode=yes \
               -o StrictHostKeyChecking=no \
               "${SSH_USER}@${IP}" \
               "sudo test -f /opt/openshift/mco-bootstrap/bootstrap/manifests/machineconfigcontroller-controllerconfig.yaml" &>/dev/null; then
            echo "✓ Manifest found"
            return 0
        fi

        sleep "$interval"
    done
}

wait_for_manifest

# Patch the bootkube ControllerConfig manifest
echo ""
echo "Patching bootkube ControllerConfig manifest with custom osImageURL and baseOSContainerImage..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${IP}" bash <<EOF
MANIFEST="/opt/openshift/mco-bootstrap/bootstrap/manifests/machineconfigcontroller-controllerconfig.yaml"

# Wait for file to exist
while ! sudo test -f "\$MANIFEST"; do
    sleep 1
done

echo "Current values:"
sudo grep -E "osImageURL|baseOSContainerImage" "\$MANIFEST"

# Patch baseOSContainerImage and osImageURL
sudo sed -i 's|baseOSContainerImage:.*|baseOSContainerImage: ${CUSTOM_OSIMAGE}|' "\$MANIFEST"
sudo sed -i 's|osImageURL:.*|osImageURL: ${CUSTOM_OSIMAGE}|' "\$MANIFEST"

echo ""
echo "New values:"
sudo grep -E "osImageURL|baseOSContainerImage" "\$MANIFEST"
EOF

echo ""
echo "=== Bootkube ControllerConfig manifest patched successfully ==="
