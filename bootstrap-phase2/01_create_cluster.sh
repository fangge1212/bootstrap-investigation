#!/bin/bash

set +x

export OPENSHIFT_INSTALL_CONFIDENTIAL_CLUSTER_CONFIG=./trustee-clevis-pin.json
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=quay.io/okd/scos-release:4.21.0-okd-scos.ec.11
#export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="quay.io/rhn_support_fjin/scos-release:4.21.0-okd-scos.ec.11-custom-v2"

kcli create kube openshift --paramfile cluster.yaml  -P pub_key=/home/fjin/.ssh/okd.pub  -f
