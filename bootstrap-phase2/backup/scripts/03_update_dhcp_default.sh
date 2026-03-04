#!/bin/bash
# Script to update DHCP host entries for multiple VMs using virsh domifaddr

# List of VMs
VMS=("test-bootstrap" "test-ctlplane-0")  # replace with your VM names

# Network name
NET="default"

for VM in "${VMS[@]}"; do
    echo "Processing VM: $VM"

    # Get the MAC and IP from virsh domifaddr
    read -r MAC IP <<< $(virsh domifaddr "$VM" | awk '/ipv4/ {split($4,a,"/"); print $2, a[1]}')

    if [[ -z "$MAC" || -z "$IP" ]]; then
        echo "Error: Could not get MAC or IP for VM $VM"
        continue
    fi

    echo "VM: $VM, MAC: $MAC, IP: $IP"

    # Build the DHCP host XML entry
    HOST_XML="<host mac='$MAC' name='$VM' ip='$IP'/>"

    # Try modify first
    if virsh net-update "$NET" modify ip-dhcp-host "$HOST_XML" --live; then
        echo "Successfully modified DHCP host for $VM"
    else
        echo "Modify failed, trying add..."
        if virsh net-update "$NET" add ip-dhcp-host "$HOST_XML" --live; then
            echo "Successfully added DHCP host for $VM"
        else
            echo "Error: failed to add DHCP host for $VM"
        fi
    fi

    echo "-----------------------------"
done
