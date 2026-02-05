#!/bin/bash
# Script to get VM IP, SSH to it, and run a command

VM="test-bootstrap"          # VM name
SSH_USER="core"              # username for SSH
REMOTE_CMD="sudo rm /opt/cni; sudo systemctl restart crio"  # command to run on VM

wait_for_vm_ssh() {
    local vm_ip="$1"
    local timeout=300   # seconds
    local interval=5
    local elapsed=0

    echo "Waiting for VM $vm_ip to be reachable via SSH..."

    while true; do
        if ssh -o ConnectTimeout=3 \
               -o BatchMode=yes \
               -o StrictHostKeyChecking=no \
               "${SSH_USER}@${vm_ip}" "echo ok" &>/dev/null; then
            echo "VM is ready for SSH."
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))

        if [[ "$elapsed" -ge "$timeout" ]]; then
            echo "ERROR: Timeout waiting for VM SSH."
            return 1
        fi
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

# Get the IP address from virsh domifaddr
IP=$(virsh domifaddr "$VM" | awk '/ipv4/ {split($4,a,"/"); print a[1]}')

if [[ -z "$IP" ]]; then
    echo "Error: Could not get IP for VM $VM"
    exit 1
fi

echo "VM $VM IP: $IP"

wait_for_vm_ssh "$IP"

# SSH into the VM and run the command
echo "SSH to $VM and run $REMOTE_CMD"
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${IP}" "$REMOTE_CMD"
