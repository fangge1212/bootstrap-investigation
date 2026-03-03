# OpenShift Confidential Cluster Bootstrap Guide

This guide helps you create an OpenShift confidential cluster using the provided automation scripts.

## Prerequisites

- RHEL/CentOS host with KVM/libvirt installed
- **kcli** tool installed and configured
  - Used to create and manage cluster VMs
  - Verify installation: `kcli list vms`
  - Ensure default libvirt connection is working
- SSH key pair generated (`~/.ssh/id_rsa.pub` or `~/.ssh/id_ed25519.pub`)
- OpenShift installer binary (`openshift-install`)
- Required base images:
  - Fedora Cloud Base: `/var/lib/libvirt/images/Fedora-Cloud-Base-Generic-43-1.6.x86_64.qcow2`
  - CentOS Stream CoreOS: `/var/lib/libvirt/images/centos-stream-coreos-10.0.20251113-0-qemu.x86_64.qcow2`
    - See [Building CentOS Stream CoreOS](#building-centos-stream-coreos) section below for build instructions

## Building CentOS Stream CoreOS

The CentOS Stream CoreOS image is built following the instructions from [trusted-execution-clusters/investigations/coreos](https://github.com/trusted-execution-clusters/investigations/tree/main/coreos).

### Steps to Build

1. **Set the OpenShift Install Release Image Override**

   This overrides the OKD version used by the OpenShift installer:
   ```bash
   export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=quay.io/okd/scos-release:4.21.0-okd-scos.ec.11
   ```

2. **Identify the CentOS Stream Image for the OKD Release**

   ```bash
   oc adm release info --image-for=stream-coreos $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE
   ```

   Example output:
   ```
   quay.io/okd/scos-content@sha256:0c00cdfc08c157bba474f9f0e40870782bed71e86a03f883227ed1c79def531e
   ```

3. **Update the Build Script**

   Replace the image in the [justfile](https://github.com/trusted-execution-clusters/investigations/blob/main/coreos/justfile#L3) with the image obtained from step 2.

4. **Build the SCOS Image**

   ```bash
   just os=scos build oci-archive init build-qemu
   ```

This will generate the CentOS Stream CoreOS image with confidential computing support that you need for the cluster.

## Installation Steps

### Step 0: Create HAProxy Load Balancer

```bash
sudo ./00_create_haproxy_vm.sh
```

This script:
- Creates a Fedora VM for HAProxy
- Installs and configures HAProxy
- Sets up VIP (192.168.122.252) for both API and Ingress
- Configures load balancing for:
  - Kubernetes API (port 6443)
  - Machine Config Server (port 22624)
  - Ingress HTTP/HTTPS (ports 80/443)


### Step 1: Create the Cluster

#### Cluster Configuration

Before creating the cluster, configure the following files:

**cluster.yaml**

Edit `cluster.yaml` to customize your cluster settings:
- `cluster`: Cluster name (default: `test`)
- `domain`: Base domain (default: `confidential-cluster.org`)
- `image`: Path to CoreOS image
- `version` and `tag`: OpenShift version (e.g., `4.21`)
- `okd`: Set to `true` for OKD, `false` for OCP
- `pub_key`: Path to SSH public key for VM access
- `manifests`: Path to custom manifests directory
- `ctlplanes`: Number of control plane nodes (default: `1`)
- `workers`: Number of worker nodes (default: `0`)
- `memory`: Control plane memory in MB (default: `20480`)
- `numcpus`: Control plane CPU count (default: `16`)
- `bootstrap_memory`: Bootstrap memory in MB (default: `16384`)
- `bootstrap_vcpus`: Bootstrap CPU count (default: `8`)
- `bootstrap_mac`: MAC address for bootstrap node
- `vmrules`: VM-specific rules (e.g., `tpm: true` for confidential computing)

**trustee-clevis-pin.json**

The **`trustee-clevis-pin.json`** file contains the Clevis pin configuration for disk encryption with Trustee attestation. This file is passed to `openshift-install` as an environment variable during cluster creation:


#### Create Cluster

```bash
sudo ./01_create_cluster.sh
```

This script:
- Uses `kcli` to create bootstrap and control plane VMs based on `cluster.yaml`

### Step 2: Restart Bootstrap

```bash
sudo ./01_restart_bootstrap.sh
```

This script:
- Destroys the bootstrap VM
- Updates ignition version to 3.6.0-experimental
- Adds attestation configuration for confidential computing
- Cleans up TPM state
- Recreates the bootstrap VM

### Step 3: Update DHCP Configuration

```bash
sudo ./03_update_dhcp_default.sh
```

Updates the default libvirt network DHCP configuration for cluster nodes, so the node ip will persist across reboot.

### Step 4: Update HAProxy Configuration

```bash
sudo ./04_update_haproxy.sh
```

Updates HAProxy backend servers if node IPs change.

### Step 5a: Remove CNI from Bootstrap

```bash
sudo ./05a_rm_cni_bootstrap.sh
```

Removes CNI configuration from the bootstrap node to workaround a bug in scos image.

### Step 5c: Patch MCC Ignition Version

```bash
sudo ./05c_patch_mcc_ignition_version.sh
```

Patches the Machine Config Controller ignition version. Machine Config Operator doesn't support 3.6.0-experimental, so we need to modify ignition version in MCC bootstrap manifests from 3.6.0-experimental to 3.5.0, or MCC bootstrap will fail.

### Step 6: Restart Control Plane

```bash
sudo ./06_restart_ctlplane.sh
```

This script:
- Destroys the control plane VM
- Updates ignition version to 3.6.0-experimental
- Adds attestation configuration
- Cleans up TPM state and storage
- Recreates the control plane VM

### Step 7a: Patch MachineConfig Ignition Version

```bash
sudo ./07a_patch_machineconfig_ignition_version.sh
```

Patches ignition version in MachineConfig resources. Machine Config Operator doesn't support 3.6.0-experimental, so we need to modify ignition version in the machine configs from 3.6.0-experimental to 3.5.0, or MCO can't start.

### Step 7c: Pause Master MCP

```bash
sudo ./07c_pause_master_mcp_incluster.sh
```

Pauses the master Machine Config Pool to prevent automatic updates.

## Cluster Teardown

### Delete Cluster

```bash
sudo ./08_delete_cluster.sh
```

Destroys all cluster VMs and cleans up resources.

## Troubleshooting

### Password-less SSH Issues
If scripts fail with SSH errors:
1. Verify SSH key exists: `ls -la ~/.ssh/id_*.pub`
2. Check kcli VM info: `kcli info vm <vm_name>`
3. Manually copy key if needed: `ssh-copy-id root@<vm_ip>`

### VM Creation Failures
- Check libvirt status: `systemctl status libvirtd`
- Verify base images exist
- Check available disk space: `df -h /var/lib/libvirt/images`

### Network Issues
- Verify libvirt default network is active: `virsh net-list`
- Check HAProxy status: `ssh root@<PROXY_VM_IP> "systemctl status haproxy"`

### Bootstrap Hangs
- Check bootstrap logs: `ssh core@<BOOTSTRAP_VM_IP> "journalctl -u bootkube"`
- Monitor bootstrap progress: `openshift-install wait-for bootstrap-complete --log-level=debug`
