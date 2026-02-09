#!/bin/bash

set -e

VM_NAME="test-ctlplane-0"
VM_BASE_IMAGE="/var/lib/libvirt/images/centos-stream-coreos-10.0.20251113-0-qemu.x86_64.qcow2"

wait_for_vm_created() {
    local vm="$1"
    local timeout=120
    local interval=3
    local elapsed=0

    echo "Waiting for VM '$vm' to be created..."

    while true; do
        if virsh dominfo "$vm" &>/dev/null; then
            echo "VM '$vm' exists."
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))

        if [[ "$elapsed" -ge "$timeout" ]]; then
            echo "ERROR: VM '$vm' was not created within timeout."
            return 1
        fi
    done
}

wait_for_vm_created "$VM_NAME"

virsh destroy $VM_NAME || true
sleep 2

CTLPLANE_IGN="/var/lib/libvirt/images/test-ctlplane-0.ign"
BACKUP_FILE="/var/lib/libvirt/images/test-ctlplane-0.ign.bak"
# Create backup
echo "Creating backup: $BACKUP_FILE"
cp "$CTLPLANE_IGN" "$BACKUP_FILE"

echo "=== Update ignition version in $CTLPLANE_IGN ==="
sed -i s/3.2.0/3.6.0-experimental/  $CTLPLANE_IGN
echo "=== Updated ignition version ==="

echo "=== Adding attestation configuration to $CTLPLANE_IGN ==="
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
}' "$CTLPLANE_IGN" > "${CTLPLANE_IGN}.tmp"

# Validate the result is valid JSON
if jq empty "${CTLPLANE_IGN}.tmp" 2>/dev/null; then
    mv "${CTLPLANE_IGN}.tmp" "$CTLPLANE_IGN"
    echo "✓ Successfully added attestation configuration"
else
    echo "✗ Error: Generated invalid JSON"
    rm -f "${CTLPLANE_IGN}.tmp"
    exit 1
fi

# Show the attestation section
echo ""
echo "Added attestation configuration:"
jq '.attestation' "$CTLPLANE_IGN"

echo ""
echo "=== Complete ==="
echo "Backup saved to: $BACKUP_FILE"

UUID="$(virsh domuuid test-ctlplane-0)"
rm /var/lib/libvirt/swtpm/$UUID -rf
rm /var/lib/libvirt/images/test-ctlplane-0_0.img -f
qemu-img create -f qcow2 /var/lib/libvirt/images/test-ctlplane-0_0.img -b $VM_BASE_IMAGE 60G -F qcow2
virsh start $VM_NAME
