#!/bin/bash
set -eux

kubeadm init \
  --pod-network-cidr=10.244.0.0/16

# kubectl access
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config

# CNI (Flannel)
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
