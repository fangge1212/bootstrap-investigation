#!/bin/bash
# The current MCO doesn't support ignition 3.6.0-experimental. To unblock the bootstrap process,
# we need to SSH to the bootstrap node and modify the ignition version in Machine Config Controller bootstrap manifests.

echo "==================================================================="
echo "  Patch MCC Manifests Ignition Version on Bootstrap Node"
echo "==================================================================="
echo ""
echo "NOTE: The current MCO doesn't support ignition 3.6.0-experimental."
echo "      To unblock the bootstrap process, we need to SSH to the bootstrap node"
echo "      and modify the ignition version in Machine Config Controller bootstrap manifests."
echo ""

VM="test-bootstrap"          # VM name
SSH_USER="core"              # username for SSH
REMOTE_CMD="sudo sed -i 's/version: 3.6.0-experimental/version: 3.5.0/' /etc/mcc/bootstrap/99_openshift-machineconfig_99-worker-ssh.yaml;sudo sed -i 's/version: 3.6.0-experimental/version: 3.5.0/' /etc/mcc/bootstrap/99_openshift-installer-ignition_master.yaml;sudo sed -i 's/version: 3.6.0-experimental/version: 3.5.0/' /etc/mcc/bootstrap/99_openshift-machineconfig_99-master-ssh.yaml;sudo sed -i 's/version: 3.6.0-experimental/version: 3.5.0/' /etc/mcc/bootstrap/99_openshift-installer-ignition_worker.yaml"  # command to run on VM

wait_for_mcc() {
    local vm_ip="$1"
    local interval=5

    echo "Waiting for dir /etc/mcc to appear on bootstrap VM"

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

echo "=== Getting bootstrap VM IP address ==="
# Get the IP address from virsh domifaddr
IP=$(virsh domifaddr "$VM" | awk '/ipv4/ {split($4,a,"/"); print a[1]}')

if [[ -z "$IP" ]]; then
    echo "Error: Could not get IP for VM $VM"
    exit 1
fi

echo "VM $VM IP: $IP"
echo ""

wait_for_mcc $IP

echo ""
echo "=== Patching ignition version from 3.6.0-experimental to 3.5.0 ==="
echo "Target files in /etc/mcc/bootstrap/:"
echo "  - 99_openshift-machineconfig_99-worker-ssh.yaml"
echo "  - 99_openshift-installer-ignition_master.yaml"
echo "  - 99_openshift-machineconfig_99-master-ssh.yaml"
echo "  - 99_openshift-installer-ignition_worker.yaml"
echo ""
# SSH into the VM and run the command
echo "Executing remote commands on $VM..."
ssh -o StrictHostKeyChecking=no "${SSH_USER}@${IP}" "$REMOTE_CMD"

echo ""
echo "=== Patch complete ==="
echo "==================================================================="
