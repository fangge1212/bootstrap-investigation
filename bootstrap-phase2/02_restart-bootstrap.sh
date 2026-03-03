#!/bin/bash

set -euo pipefail

VM_NAME="test-bootstrap"
VM_BASE_IMAGE="/var/lib/libvirt/images/centos-stream-coreos-10.0.20251113-0-qemu.x86_64.qcow2"

wait_for_vm_created() {
    local vm="$1"
    local interval=3

    echo "Waiting for VM '$vm' to be created..."

    while true; do
        if virsh dominfo "$vm" &>/dev/null; then
            echo "VM '$vm' exists."
            return 0
        fi

        sleep "$interval"
    done
}

wait_for_vm_created "$VM_NAME"

virsh destroy $VM_NAME || true
sleep 2

BOOTSTRAP_IGN="/var/lib/libvirt/images/test-bootstrap.ign"
BACKUP_FILE="/var/lib/libvirt/images/test-bootstrap.ign.bak"
# Create backup
echo "Creating backup: $BACKUP_FILE"
cp "$BOOTSTRAP_IGN" "$BACKUP_FILE"

echo "=== Update ignition version in $BOOTSTRAP_IGN ==="
sed -i s/3.2.0/3.6.0-experimental/  $BOOTSTRAP_IGN
echo "=== Updated ignition version ==="

echo "=== Adding attestation configuration to $BOOTSTRAP_IGN ==="
# Add attestation section using jq
echo "Adding attestation configuration..."
jq '. + {
    "attestation": {
        "attestation_key": {
            "registration": {
                "certificat": "",
                "url": "http://10.73.211.28:9001/register-ak"
            }
        }
    }
}' "$BOOTSTRAP_IGN" > "${BOOTSTRAP_IGN}.tmp"

# Validate the result is valid JSON
if jq empty "${BOOTSTRAP_IGN}.tmp" 2>/dev/null; then
    mv "${BOOTSTRAP_IGN}.tmp" "$BOOTSTRAP_IGN"
    echo "✓ Successfully added attestation configuration"
else
    echo "✗ Error: Generated invalid JSON"
    rm -f "${BOOTSTRAP_IGN}.tmp"
    exit 1
fi

# Show the attestation section
echo ""
echo "Added attestation configuration:"
jq '.attestation' "$BOOTSTRAP_IGN"

echo ""
echo "=== Complete ==="
echo "Backup saved to: $BACKUP_FILE"

UUID="$(virsh domuuid $VM_NAME)"
rm /var/lib/libvirt/swtpm/$UUID -rf
rm /var/lib/libvirt/images/test-bootstrap_0.img -f
qemu-img create -f qcow2 /var/lib/libvirt/images/test-bootstrap_0.img -b $VM_BASE_IMAGE 60G -F qcow2
virsh start $VM_NAME
