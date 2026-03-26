#!/bin/bash
# Workaround https://github.com/okd-project/okd/issues/2296

echo "==================================================================="
echo "  Remove /opt/cni Symlink from Bootstrap Node"
echo "==================================================================="
echo ""
echo "PURPOSE: Remove the /opt/cni symlink from the bootstrap node to"
echo "         workaround a bug in the SCOS image."
echo ""
echo "BACKGROUND: There is a known issue where the /opt/cni symlink on the"
echo "            bootstrap node causes problems during cluster setup."
echo "            See: https://github.com/okd-project/okd/issues/2296"
echo ""
echo "==================================================================="
echo ""

VM="test-bootstrap"          # VM name
SSH_USER="core"              # username for SSH
REMOTE_CMD="sudo rm /opt/cni"  # command to run on VM
#REMOTE_CMD="sudo rm /opt/cni; sudo systemctl restart crio"  # command to run on VM

wait_for_vm_ssh() {
    local vm_ip="$1"
    local interval=5

    echo "Waiting for bootstrap VM to be reachable via SSH..."

    while true; do
        if ssh -o ConnectTimeout=3 \
               -o BatchMode=yes \
               -o StrictHostKeyChecking=no \
               "${SSH_USER}@${vm_ip}" "echo ok" &>/dev/null; then
            echo "VM is ready for SSH."
            return 0
        fi

        sleep "$interval"
    done
}

wait_for_vm_running() {
    local vm_name="$1"

    echo "Waiting for VM $vm_name to start..."

    while [[ "$(virsh domstate "$vm_name")" != "running" ]]; do
        sleep 2
    done

    echo "VM is running."
}

wait_for_vm_running "$VM"

echo ""
echo "=== Getting bootstrap VM IP address ==="
# Get the IP address from virsh domifaddr
IP=$(virsh domifaddr "$VM" | awk '/ipv4/ {split($4,a,"/"); print a[1]}')

if [[ -z "$IP" ]]; then
    echo "Error: Could not get IP for VM $VM"
    exit 1
fi

echo "VM $VM IP: $IP"
echo ""

wait_for_vm_ssh "$IP"

echo ""
echo "=== Removing /opt/cni symlink ==="
# SSH into the VM and run the command
echo "Executing command on $VM: $REMOTE_CMD"
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${IP}" "$REMOTE_CMD"

echo ""
echo "=== /opt/cni symlink removed successfully ==="
echo "==================================================================="
