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
NEW_VERSION="3.6.0-experimental"
jq --arg new_ver "$NEW_VERSION" '.ignition.version = $new_ver' "$BOOTSTRAP_IGN" > "${BOOTSTRAP_IGN}.tmp" && mv "${BOOTSTRAP_IGN}.tmp" "$BOOTSTRAP_IGN"
echo "=== Updated ignition version ==="

echo "=== Complete ==="
echo "Backup saved to: $BACKUP_FILE"

UUID="$(virsh domuuid $VM_NAME)"
rm /var/lib/libvirt/swtpm/$UUID -rf
rm /var/lib/libvirt/images/test-bootstrap_0.img -f
qemu-img create -f qcow2 /var/lib/libvirt/images/test-bootstrap_0.img -b $VM_BASE_IMAGE 60G -F qcow2
virsh start $VM_NAME
