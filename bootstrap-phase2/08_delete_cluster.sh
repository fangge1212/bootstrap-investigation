#!/bin/bash

set +x

kcli delete cluster test -y
rm -rf /var/lib/libvirt/swtpm/
