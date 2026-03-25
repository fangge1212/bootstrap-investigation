#!/bin/bash
# Script to pause master MachineConfigPool in-cluster
set -e

KUBECONFIG="/root/.kcli/clusters/test/auth/kubeconfig"

echo "=== Pausing master MachineConfigPool in-cluster ==="

# Wait for the API server to be available
wait_for_api() {
    local interval=5

    echo "Waiting for API server to be available..."

    while true; do
        if oc --kubeconfig="${KUBECONFIG}" get nodes &>/dev/null; then
            echo "✓ API server is ready"
            return 0
        fi

        sleep "$interval"
    done
}

# Wait for MachineConfigPool to be created
wait_for_mcp() {
    local interval=2

    echo "Waiting for master MachineConfigPool to be created..."

    while true; do
        if oc --kubeconfig="${KUBECONFIG}" get mcp master &>/dev/null; then
            echo "✓ Master MachineConfigPool found"
            return 0
        fi

        sleep "$interval"
    done
}

wait_for_api
wait_for_mcp

echo ""
echo "Current master MachineConfigPool paused status:"
CURRENT_PAUSED=$(oc --kubeconfig="${KUBECONFIG}" get mcp master -o jsonpath='{.spec.paused}')
echo "paused: $CURRENT_PAUSED"

if [ "$CURRENT_PAUSED" = "true" ]; then
    echo ""
    echo "✓ Master MachineConfigPool is already paused"
    exit 0
fi

echo ""
echo "Patching master MachineConfigPool to set paused: true..."

oc --kubeconfig="${KUBECONFIG}" patch mcp master \
    --type=merge \
    -p '{"spec":{"paused":true}}'

echo ""
echo "Verification - New paused status:"
NEW_PAUSED=$(oc --kubeconfig="${KUBECONFIG}" get mcp master -o jsonpath='{.spec.paused}')
echo "paused: $NEW_PAUSED"

if [ "$NEW_PAUSED" = "true" ]; then
    echo ""
    echo "✓ Master MachineConfigPool successfully paused!"
    echo ""
    echo "Note: This prevents normal MachineConfig updates, but does NOT prevent"
    echo "      the initial bootstrap pivot during first boot."
else
    echo ""
    echo "✗ Failed to pause master MachineConfigPool"
    exit 1
fi

echo ""
echo "=== Master MachineConfigPool pause complete ==="
