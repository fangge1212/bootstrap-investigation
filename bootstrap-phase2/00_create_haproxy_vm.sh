#!/bin/bash

set -euo pipefail

# VM Configuration
VM_NAME="haproxy"
VM_MEMORY=1024
VM_CPUS=1
VM_DISK=10
VM_NETWORK="default"
VM_IP="192.168.122.251"
VM_IMAGE="/var/lib/libvirt/images/Fedora-Cloud-Base-Generic-43-1.6.x86_64.qcow2"

# IP Addresses for haproxy
VIP="192.168.122.252"  # Same IP for both API and Ingress
INTERFACE="ens3"

# Backend servers
BOOTSTRAP_IP="192.168.122.56"
CTLPLANE_IP="192.168.122.242"

echo "=== Creating haproxy VM ==="
kcli create vm $VM_NAME \
    -P memory=$VM_MEMORY \
    -P numcpus=$VM_CPUS \
    -P disk=$VM_DISK \
    -P network=$VM_NETWORK \
    -P ip=$VM_IP \
    -P image=$VM_IMAGE

echo "=== Waiting for VM to be ready ==="
sleep 30

# Get the actual IP address assigned to the VM
echo "=== Getting VM IP address ==="
ACTUAL_IP=$(kcli info vm $VM_NAME -f ip -v 2>/dev/null || virsh domifaddr $VM_NAME | grep -oP '192\.168\.122\.\d+' | head -1 || echo "$VM_IP")
echo "VM IP: $ACTUAL_IP"

# Wait for SSH to be available with password-less login
echo "=== Waiting for password-less SSH to be available ==="
echo "Note: kcli should automatically inject your SSH key (~/.ssh/id_rsa.pub or ~/.ssh/id_ed25519.pub)"
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    # Try SSH with BatchMode to ensure it's password-less (will fail if password is required)
    if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 root@$ACTUAL_IP "echo 'SSH ready'" 2>/dev/null; then
        echo "✓ Password-less SSH is working"
        break
    fi
    echo "Waiting for password-less SSH... (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
    sleep 10
    RETRY_COUNT=$((RETRY_COUNT+1))
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "✗ Error: Password-less SSH connection failed"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check if your SSH key exists: ls -la ~/.ssh/id_*.pub"
    echo "2. Verify kcli injected the key: kcli info vm $VM_NAME"
    echo "3. Try manual SSH: ssh root@$ACTUAL_IP"
    echo "4. If needed, manually copy your key: ssh-copy-id root@$ACTUAL_IP"
    exit 1
fi

echo "=== Installing and configuring haproxy ==="

# Install haproxy
ssh -o StrictHostKeyChecking=no root@$ACTUAL_IP "dnf install -y haproxy"

# Enable haproxy
ssh -o StrictHostKeyChecking=no root@$ACTUAL_IP "systemctl enable haproxy"

# Add VIP address to the network interface
echo "=== Adding VIP address ==="
ssh -o StrictHostKeyChecking=no root@$ACTUAL_IP "ip addr add ${VIP}/24 dev ${INTERFACE}"

# Create Kubernetes-specific haproxy configuration to append
echo "=== Creating Kubernetes haproxy configuration ==="
cat > /tmp/haproxy-k8s.cfg << 'EOF'

# -------------------------
# Kubernetes API (6443)
# -------------------------
frontend api
    bind 192.168.122.252:6443
    mode tcp
    default_backend api_backend

backend api_backend
    balance roundrobin
    mode tcp
    server test-ctlplane-0   192.168.122.242:6443 check
    server test-bootstrap    192.168.122.56:6443 check

# -------------------------
# Machine Config Server (22623)
# -------------------------
frontend mcs
    bind 192.168.122.252:22624
    mode tcp
    default_backend mcs_backend

backend mcs_backend
    balance roundrobin
    mode tcp
    server test-bootstrap 192.168.122.56:22624 check

# -------------------------
# Ingress HTTP/HTTPS
# -------------------------
frontend ingress_http
    bind 192.168.122.252:80
    mode tcp
    default_backend ingress_backend

frontend ingress_https
    bind 192.168.122.252:443
    mode tcp
    default_backend ingress_backend

backend ingress_backend
    balance roundrobin
    mode tcp
    server test-ctlplane-0 192.168.122.242:80 check
EOF

# Backup the original haproxy.cfg
echo "=== Backing up original haproxy configuration ==="
ssh -o StrictHostKeyChecking=no root@$ACTUAL_IP "cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak"

# Copy Kubernetes config snippet to the VM and append to haproxy.cfg
echo "=== Appending Kubernetes configuration to haproxy.cfg ==="
scp -o StrictHostKeyChecking=no /tmp/haproxy-k8s.cfg root@$ACTUAL_IP:/tmp/
ssh -o StrictHostKeyChecking=no root@$ACTUAL_IP "cat /tmp/haproxy-k8s.cfg >> /etc/haproxy/haproxy.cfg"
ssh -o StrictHostKeyChecking=no root@$ACTUAL_IP "rm /tmp/haproxy-k8s.cfg"

# Validate haproxy configuration
echo "=== Validating haproxy configuration ==="
ssh -o StrictHostKeyChecking=no root@$ACTUAL_IP "haproxy -c -f /etc/haproxy/haproxy.cfg"

# Restart haproxy
echo "=== Restarting haproxy service ==="
ssh -o StrictHostKeyChecking=no root@$ACTUAL_IP "systemctl restart haproxy"

# Verify haproxy is running
echo "=== Verifying haproxy status ==="
ssh -o StrictHostKeyChecking=no root@$ACTUAL_IP "systemctl status haproxy --no-pager"

# Show the configured IP addresses
echo ""
echo "=== Configured IP addresses ==="
ssh -o StrictHostKeyChecking=no root@$ACTUAL_IP "ip addr show dev ${INTERFACE}"

echo ""
echo "=== haproxy VM setup complete ==="
echo "VM IP: $ACTUAL_IP"
echo "VIP: $VIP (used for both API and Ingress)"
echo ""
echo "Add the following to your client machine's /etc/hosts:"
echo "  ${VIP} api.test.confidential-cluster.org api-int.test.confidential-cluster.org apps.test.confidential-cluster.org"

# Clean up temp file
rm -f /tmp/haproxy-k8s.cfg
