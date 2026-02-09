#!/bin/bash

set -euo pipefail

VM_NAME="test-bootstrap"
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

virsh destroy $VM_NAME
sleep 2
UUID="$(virsh domuuid $VM_NAME)"
rm /var/lib/libvirt/swtpm/$UUID -rf
rm /var/lib/libvirt/images/test-bootstrap_0.img -f
qemu-img create -f qcow2 /var/lib/libvirt/images/test-bootstrap_0.img -b $VM_BASE_IMAGE 60G -F qcow2
virsh start $VM_NAME
