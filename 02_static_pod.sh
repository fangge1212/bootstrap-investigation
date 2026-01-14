#!/bin/bash
set -eux

cat <<'EOF' >/etc/kubernetes/manifests/hello-static.yaml
apiVersion: v1
kind: Pod
metadata:
  name: hello-static
  namespace: kube-system
spec:
  hostNetwork: true
  restartPolicy: Always
  containers:
  - name: hello
    image: busybox:1.36
    command:
    - /bin/sh
    - -c
    - |
      echo "Static pod started on $(hostname)"
      while true; do sleep 30; done
    resources:
      requests:
        cpu: 10m
        memory: 16Mi
EOF
