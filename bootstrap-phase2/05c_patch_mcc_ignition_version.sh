#!/bin/bash
# Because the current mco doesn't ignition 3.6.0-experimental, so we need to
# SSH to bootstrap node, modify the ignition version in Machine Config Controller bootstrap manifests.

VM="test-bootstrap"          # VM name
SSH_USER="core"              # username for SSH
REMOTE_CMD="sudo sed -i 's/version: 3.6.0-experimental/version: 3.5.0/' /etc/mcc/bootstrap/99_openshift-machineconfig_99-worker-ssh.yaml;sudo sed -i 's/version: 3.6.0-experimental/version: 3.5.0/' /etc/mcc/bootstrap/99_openshift-installer-ignition_master.yaml;sudo sed -i 's/version: 3.6.0-experimental/version: 3.5.0/' /etc/mcc/bootstrap/99_openshift-machineconfig_99-master-ssh.yaml;sudo sed -i 's/version: 3.6.0-experimental/version: 3.5.0/' /etc/mcc/bootstrap/99_openshift-installer-ignition_worker.yaml"  # command to run on VM

wait_for_mcc() {
    local vm_ip="$1"
    local interval=5

    echo "Waiting for dir /etc/mcc to appear on VM $vm_ip"

    while true; do
        if ssh -o ConnectTimeout=3 \
               -o BatchMode=yes \
               -o StrictHostKeyChecking=no \
               "${SSH_USER}@${vm_ip}" "[ -d /etc/mcc ]" &>/dev/null; then
            echo "Dir /etc/mcc exists."
            return 0
        fi

        sleep "$interval"
    done
}

# Get the IP address from virsh domifaddr
IP=$(virsh domifaddr "$VM" | awk '/ipv4/ {split($4,a,"/"); print a[1]}')

if [[ -z "$IP" ]]; then
    echo "Error: Could not get IP for VM $VM"
    exit 1
fi

echo "VM $VM IP: $IP"

wait_for_mcc $IP

# SSH into the VM and run the command
echo "SSH to $VM and run $REMOTE_CMD"
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${IP}" "$REMOTE_CMD"
