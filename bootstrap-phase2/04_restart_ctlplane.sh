#!/bin/bash

set -e

VM_NAME="test-ctlplane-0"
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

echo ""
echo "=== Stopping VM '$VM_NAME' ==="
virsh destroy $VM_NAME || true
sleep 2
echo "VM '$VM_NAME' stopped successfully"

echo ""
echo "=== Backing up ignition configuration ==="
CTLPLANE_IGN="/var/lib/libvirt/images/test-ctlplane-0.ign"
BACKUP_FILE="/var/lib/libvirt/images/test-ctlplane-0.ign.bak"
echo "Creating backup: $BACKUP_FILE"
cp "$CTLPLANE_IGN" "$BACKUP_FILE"

echo "=== Update ignition version in $CTLPLANE_IGN ==="
NEW_VERSION="3.6.0-experimental"
jq --arg new_ver "$NEW_VERSION" '.ignition.version = $new_ver' "$CTLPLANE_IGN" > "${CTLPLANE_IGN}.tmp" && mv "${CTLPLANE_IGN}.tmp" "$CTLPLANE_IGN"
echo "=== Updated ignition version ==="

echo ""
echo "=== Ignition configuration update complete ==="
echo "Backup saved to: $BACKUP_FILE"

echo ""
echo "=== Cleaning up VM resources ==="
UUID="$(virsh domuuid test-ctlplane-0)"
echo "Removing TPM data for UUID: $UUID"
rm /var/lib/libvirt/swtpm/$UUID -rf
echo "Removing old disk image"
rm /var/lib/libvirt/images/test-ctlplane-0_0.img -f
echo "Creating new disk image based on: $VM_BASE_IMAGE"
qemu-img create -f qcow2 /var/lib/libvirt/images/test-ctlplane-0_0.img -b $VM_BASE_IMAGE 60G -F qcow2
echo "Disk image created successfully"

echo ""
echo "=== Starting VM '$VM_NAME' ==="
virsh start $VM_NAME
echo "VM '$VM_NAME' started successfully"
echo ""
echo "=== Script complete ==="
