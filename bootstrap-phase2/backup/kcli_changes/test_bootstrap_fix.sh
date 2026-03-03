#!/bin/bash
# Test script to verify bootstrap.ign fix

CLUSTER="test"
CLUSTER_DIR="/root/.kcli/clusters/${CLUSTER}"

echo "Testing bootstrap.ign fix..."
echo ""

echo "After recreating the cluster, bootstrap.ign should contain:"
echo "1. The FULL bootstrap configuration (not just a pointer)"
echo "2. All custom sources from openshift-install"
echo ""

echo "To test:"
echo "1. Delete current cluster: kcli delete cluster ${CLUSTER}"
echo "2. Recreate cluster with your customized openshift-install"
echo "3. Check bootstrap.ign:"
echo ""
echo "   jq '.ignition.config.merge' ${CLUSTER_DIR}/bootstrap.ign"
echo ""
echo "Expected: Should show custom Clevis/Trustee source"
echo "   OR"
echo "   If bootstrap.ign doesn't use merge sources, it should be"
echo "   identical to bootstrap.ign.ori (the original from openshift-install)"
echo ""
echo "4. Verify all sources:"
echo "   ${PWD}/QUICK_VERIFICATION.sh ${CLUSTER}"
