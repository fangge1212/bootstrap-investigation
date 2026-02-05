#!/bin/bash                                                                                                                             
set -e

NAMESPACE="trusted-execution-clusters"

echo "=== Cleaning up operator resources in namespace: $NAMESPACE ==="
echo

# Function to remove finalizers from a resource
remove_finalizers() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3

    echo "Removing finalizers from $resource_type/$resource_name..."
    kubectl patch $resource_type $resource_name -n $namespace \
        --type=json \
        -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>&1

    if [ $? -eq 0 ]; then
        echo "✓ Successfully patched $resource_type/$resource_name"
    else
        echo "✗ Failed to patch $resource_type/$resource_name (may not have finalizers)"
    fi
    echo
  }

# Clean up secrets
echo "--- Processing secrets ---"
SECRETS=$(kubectl get secrets -n $NAMESPACE -o name 2>/dev/null || true)
if [ -n "$SECRETS" ]; then
    for secret in $SECRETS; do
        SECRET_NAME=$(echo $secret | cut -d'/' -f2)
        remove_finalizers "secrets" "$SECRET_NAME" "$NAMESPACE"
    done
else
    echo "No secrets matching 'ak-*' found"
    echo
fi

# Clean up approvedimages
echo "--- Processing approvedimages ---"
APPROVED_IMAGES=$(kubectl get approvedimages -n $NAMESPACE -o name 2>/dev/null || true)
if [ -n "$APPROVED_IMAGES" ]; then
    for img in $APPROVED_IMAGES; do
        IMG_NAME=$(echo $img | cut -d'/' -f2)
        remove_finalizers "approvedimage" "$IMG_NAME" "$NAMESPACE"
    done
else
    echo "No approvedimages found"
    echo
fi

# Clean up machines
echo "--- Processing machines ---"
MACHINES=$(kubectl get machines -n $NAMESPACE -o name 2>/dev/null || true)
if [ -n "$MACHINES" ]; then
    for machine in $MACHINES; do
        MACHINE_NAME=$(echo $machine | cut -d'/' -f2)
        remove_finalizers "machines" "$MACHINE_NAME" "$NAMESPACE"
    done
else
    echo "No machines found"
    echo
fi

echo "=== Cleanup complete ==="
