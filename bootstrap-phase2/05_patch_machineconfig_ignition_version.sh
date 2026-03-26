#!/bin/bash
# Script to patch MachineConfig ignition versions to 3.5.0

set -e

echo "==================================================================="
echo "  Patch MachineConfig Ignition Versions In-Cluster"
echo "==================================================================="
echo ""
echo "PURPOSE: Patch the ignition version in MachineConfig cluster resources"
echo "         from 3.6.0-experimental to 3.5.0 for MCO compatibility."
echo ""
echo "BACKGROUND: The current MCO doesn't support ignition 3.6.0-experimental."
echo "            Even though Step 3 patched the source manifests on the bootstrap"
echo "            node, the resulting MachineConfig objects in the cluster may still"
echo "            have 3.6.0-experimental, causing MCO to fail with:"
echo ""
echo '            "Failed to render configuration: unknown version.'
echo '             Supported spec versions: 2.2,3.0,3.1,3.2,3.3,3.4,3.5"'
echo ""
echo "            This script patches the actual Kubernetes MachineConfig objects"
echo "            to ensure MCO can successfully render configurations."
echo ""
echo "==================================================================="
echo ""

KUBECONFIG="${KUBECONFIG:-/root/.kcli/clusters/test/auth/kubeconfig}"
export KUBECONFIG

IGNITION_VERSION="3.5.0"
RETRY_INTERVAL=5

MACHINE_CONFIGS=(
    "99-installer-ignition-master"
    "99-installer-ignition-worker"
    "99-master-ssh"
    "99-worker-ssh"
)

echo "=== Waiting for API server to be accessible ==="
while ! oc whoami &>/dev/null; do
    echo "Waiting for API server... (retrying in ${RETRY_INTERVAL}s)"
    sleep ${RETRY_INTERVAL}
done
echo "✓ API server is accessible"
echo ""

echo "=== Waiting for MachineConfigs to exist ==="
for mc in "${MACHINE_CONFIGS[@]}"; do
    echo "Checking MachineConfig: $mc"
    while ! oc get machineconfig "$mc" &>/dev/null; do
        echo "  Waiting for $mc to exist... (retrying in ${RETRY_INTERVAL}s)"
        sleep ${RETRY_INTERVAL}
    done
    echo "  ✓ MachineConfig exists: $mc"
done
echo "✓ All MachineConfigs exist"
echo ""

echo "=== Patching MachineConfig ignition versions to ${IGNITION_VERSION} ==="

for mc in "${MACHINE_CONFIGS[@]}"; do
    echo "Patching MachineConfig: $mc"
    oc patch machineconfig "$mc" --type='json' \
        -p="[{\"op\": \"replace\", \"path\": \"/spec/config/ignition/version\", \"value\": \"${IGNITION_VERSION}\"}]"

    if [ $? -eq 0 ]; then
        echo "✓ Successfully patched $mc"
    else
        echo "✗ Failed to patch $mc"
        exit 1
    fi
    echo ""
done

echo "=== Verifying changes ==="
for mc in "${MACHINE_CONFIGS[@]}"; do
    version=$(oc get machineconfig "$mc" -o jsonpath='{.spec.config.ignition.version}')
    echo "$mc: ignition version = $version"
done

echo ""
echo "=== Patch complete ==="
echo "==================================================================="
