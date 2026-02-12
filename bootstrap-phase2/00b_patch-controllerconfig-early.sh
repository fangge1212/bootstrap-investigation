#!/bin/bash
# Script to patch in-cluster ControllerConfig early during bootstrap
set -e

KUBECONFIG="${KUBECONFIG:-/root/.kcli/clusters/test/auth/kubeconfig}"
export KUBECONFIG

CUSTOM_OSIMAGE="quay.io/rhn_support_fjin/scos@sha256:c6cee984d9610b70a1bd1600bf6ce798e04542227690cc24ae4b41620ac4d0e5"

echo "=== Waiting for cluster API to be available ==="

wait_for_api() {
    local timeout=1200  # 20 minutes
    local interval=5
    local elapsed=0

    while true; do
        if oc get nodes &>/dev/null 2>&1; then
            echo "✓ API is available"
            return 0
        fi

        echo "Waiting for API... ($elapsed/$timeout seconds)"
        sleep "$interval"
        elapsed=$((elapsed + interval))

        if [ $elapsed -ge $timeout ]; then
            echo "✗ Timeout waiting for API"
            return 1
        fi
    done
}

wait_for_api

echo ""
echo "=== Waiting for ControllerConfig to be created ==="

wait_for_controllerconfig() {
    local timeout=300
    local interval=5
    local elapsed=0

    while true; do
        if oc get controllerconfig machine-config-controller &>/dev/null 2>&1; then
            echo "✓ ControllerConfig exists"
            return 0
        fi

        echo "Waiting for ControllerConfig... ($elapsed/$timeout seconds)"
        sleep "$interval"
        elapsed=$((elapsed + interval))

        if [ $elapsed -ge $timeout ]; then
            echo "✗ Timeout waiting for ControllerConfig"
            return 1
        fi
    done
}

wait_for_controllerconfig

echo ""
echo "=== Checking current osImageURL and baseOSContainerImage ==="
CURRENT_OSIMAGE=$(oc get controllerconfig machine-config-controller -o jsonpath='{.spec.osImageURL}')
CURRENT_BASEOSIMAGE=$(oc get controllerconfig machine-config-controller -o jsonpath='{.spec.baseOSContainerImage}')
echo "Current osImageURL: $CURRENT_OSIMAGE"
echo "Current baseOSContainerImage: $CURRENT_BASEOSIMAGE"

if [ "$CURRENT_OSIMAGE" = "$CUSTOM_OSIMAGE" ] && [ "$CURRENT_BASEOSIMAGE" = "$CUSTOM_OSIMAGE" ]; then
    echo "✓ Both fields already set to custom image, no patch needed"
    exit 0
fi

echo ""
echo "=== Patching ControllerConfig with custom osImageURL and baseOSContainerImage ==="
oc patch controllerconfig machine-config-controller --type='json' \
    -p="[{\"op\": \"replace\", \"path\": \"/spec/osImageURL\", \"value\": \"${CUSTOM_OSIMAGE}\"},{\"op\": \"replace\", \"path\": \"/spec/baseOSContainerImage\", \"value\": \"${CUSTOM_OSIMAGE}\"}]"

if [ $? -eq 0 ]; then
    echo "✓ Successfully patched ControllerConfig"
else
    echo "✗ Failed to patch ControllerConfig"
    exit 1
fi

echo ""
echo "=== Verifying patch ==="
NEW_OSIMAGE=$(oc get controllerconfig machine-config-controller -o jsonpath='{.spec.osImageURL}')
NEW_BASEOSIMAGE=$(oc get controllerconfig machine-config-controller -o jsonpath='{.spec.baseOSContainerImage}')
echo "New osImageURL: $NEW_OSIMAGE"
echo "New baseOSContainerImage: $NEW_BASEOSIMAGE"

if [ "$NEW_OSIMAGE" = "$CUSTOM_OSIMAGE" ] && [ "$NEW_BASEOSIMAGE" = "$CUSTOM_OSIMAGE" ]; then
    echo "✓ ControllerConfig successfully updated"
else
    echo "✗ ControllerConfig update verification failed"
    exit 1
fi

echo ""
echo "=== Patch complete - ControllerConfig updated before nodes apply configs ==="
