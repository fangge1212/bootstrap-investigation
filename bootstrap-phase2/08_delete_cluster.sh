#!/bin/bash

set +x

echo "==================================================================="
echo "  Delete OpenShift Cluster"
echo "==================================================================="
echo ""
echo "PURPOSE: Destroys all cluster VMs and cleans up resources."
echo ""
echo "This script will:"
echo "  - Delete the cluster 'test' using kcli"
echo "  - Remove all TPM state data from /var/lib/libvirt/swtpm/"
echo ""
echo "WARNING: This is a destructive operation that cannot be undone."
echo ""
echo "==================================================================="
echo ""

echo "=== Deleting cluster 'test' ==="
kcli delete cluster test -y
echo "✓ Cluster deleted"

echo ""
echo "=== Cleaning up TPM state ==="
rm -rf /var/lib/libvirt/swtpm/
echo "✓ TPM state cleaned up"

echo ""
echo "=== Cluster deletion complete ==="
echo "==================================================================="
