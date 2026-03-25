#!/bin/bash

set +x

echo "==================================================================="
echo "  OpenShift Cluster Creation Script"
echo "==================================================================="
echo ""

echo "=== Setting up environment variables ==="
echo "Configuring confidential cluster with Clevis/Trustee integration..."
export OPENSHIFT_INSTALL_CONFIDENTIAL_CLUSTER_CONFIG=./trustee-clevis-pin.json
echo "  - OPENSHIFT_INSTALL_CONFIDENTIAL_CLUSTER_CONFIG: $OPENSHIFT_INSTALL_CONFIDENTIAL_CLUSTER_CONFIG"

echo "Setting release image override..."
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=quay.io/okd/scos-release:4.21.0-okd-scos.ec.11
echo "  - OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE: $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE"

echo ""
echo "=== Creating OpenShift cluster using kcli ==="
echo "Cluster configuration file: cluster.yaml"
echo "SSH public key: /home/fjin/.ssh/okd.pub"
echo "Force mode: enabled (-f flag)"
echo ""
echo "Starting cluster creation..."
echo "-------------------------------------------------------------------"

kcli create kube openshift --paramfile cluster.yaml  -P pub_key=/home/fjin/.ssh/okd.pub  -f

echo ""
echo "-------------------------------------------------------------------"
echo "=== Cluster creation command completed ==="
echo "==================================================================="
