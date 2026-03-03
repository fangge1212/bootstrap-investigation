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
- `oc` CLI tool for image inspection
- `just` command runner (for building CoreOS image)
- Required base images:
  - Fedora Cloud Base: `/var/lib/libvirt/images/Fedora-Cloud-Base-Generic-43-1.6.x86_64.qcow2`
  - CentOS Stream CoreOS: `/var/lib/libvirt/images/centos-stream-coreos-10.0.20251113-0-qemu.x86_64.qcow2`
    - See [Building CentOS Stream CoreOS](#building-centos-stream-coreos) section below for build instructions

## Building CentOS Stream CoreOS

The CentOS Stream CoreOS (SCOS) image with confidential computing support is built following the instructions from [trusted-execution-clusters/investigations/coreos](https://github.com/trusted-execution-clusters/investigations/tree/main/coreos).

### Build Steps

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

   Replace the image in the [justfile](https://github.com/trusted-execution-clusters/investigations/blob/main/coreos/justfile#L3) with the image SHA obtained from step 2.

4. **Build the SCOS Image**

   ```bash
   just os=scos build oci-archive init build-qemu
   ```

   This generates the CentOS Stream CoreOS qcow2 image with confidential computing and TPM support.

5. **Upload SCOS Container Image to Quay.io**

   After building, you need to upload the SCOS container image to your quay.io repository so it can be referenced in manifest files:

   ```bash
   # Tag the image
   podman tag quay.io/trusted-execution-clusters/scos:latest quay.io/<your-username>/scos:4.21.0-okd-scos.ec.11

   # Login to quay.io
   podman login quay.io

   # Push the image
   podman push quay.io/<your-username>/scos:4.21.0-okd-scos.ec.11
   ```

   **Important**: Make sure the repository is public or properly configured for cluster access. The manifest files in the `manifests/` directory will reference this quay.io image URL.

## Installation Steps

### Step 0: Create HAProxy Load Balancer

```bash
sudo ./00_create_haproxy_vm.sh
```

**Purpose**: Creates and configures the load balancer for the cluster.

This script:
- Creates a Fedora VM for HAProxy
- Installs and configures HAProxy
- Sets up VIP (192.168.122.252) for both API and Ingress
- Configures load balancing for:
  - Kubernetes API (port 6443)
  - Machine Config Server (port 22624)
  - Ingress HTTP/HTTPS (ports 80/443)


---

### Step 1: Create the Cluster

#### Configuration Files

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

The `trustee-clevis-pin.json` file contains the Clevis pin configuration for disk encryption with Trustee attestation. This file is passed to `openshift-install` as an environment variable.

**Manifest Files**

The `manifests/` directory contains custom MachineConfig and other resources that will be applied during cluster installation. These manifest files reference the SCOS container image uploaded to quay.io.

If you've uploaded your SCOS image to a custom quay.io repository, update the image references in the manifest files:

```bash
# Example: Update image references in manifests
sed -i 's|osImageURL:.*|osImageURL: quay.io/<your-username>/scos@sha256:<SHA256_VALUE>|g' manifests/*.yaml
```

Make sure the image URL in your manifests matches the image you pushed to quay.io in the [Building CentOS Stream CoreOS](#building-centos-stream-coreos) section.

#### Run Cluster Creation

```bash
sudo ./01_create_cluster.sh
```

This script:
- Uses `kcli` to create bootstrap and control plane VMs based on `cluster.yaml`

---

### Step 2: Restart Bootstrap

```bash
sudo ./02_restart_bootstrap.sh
```

**Purpose**: Recreates the bootstrap VM with updated ignition configuration and attestation support.

This script:
- Destroys the bootstrap VM
- Backs up the original ignition file
- Updates ignition version to 3.6.0-experimental
- Adds attestation configuration for confidential computing
- Cleans up TPM state
- Recreates the bootstrap VM with fresh storage

---

### Step 3: Update DHCP Configuration

```bash
sudo ./03_update_dhcp_default.sh
```

**Purpose**: Configures DHCP reservations to ensure node IP addresses persist across reboots.

Updates the default libvirt network DHCP configuration for cluster nodes.

---

### Step 4: Update HAProxy Configuration

```bash
sudo ./04_update_haproxy.sh
```

**Purpose**: Updates HAProxy backend server configuration if node IPs change.

---

### Step 5a: Remove CNI from Bootstrap

```bash
sudo ./05a_rm_cni_bootstrap.sh
```

**Purpose**: Removes CNI configuration from the bootstrap node to workaround a bug in the SCOS image.

---

### Step 5c: Patch MCC Ignition Version

```bash
sudo ./05c_patch_mcc_ignition_version.sh
```

**Purpose**: Patches the Machine Config Controller ignition version for compatibility.

Machine Config Operator doesn't support ignition version 3.6.0-experimental, so this script modifies the ignition version in MCC bootstrap manifests from 3.6.0-experimental to 3.5.0, preventing MCC bootstrap failures.

---

### Step 6: Restart Control Plane

```bash
sudo ./06_restart_ctlplane.sh
```

**Purpose**: Recreates the control plane VM with updated ignition configuration and attestation support.

This script:
- Destroys the control plane VM
- Backs up the original ignition file
- Updates ignition version to 3.6.0-experimental
- Adds attestation configuration
- Cleans up TPM state and storage
- Recreates the control plane VM

---

### Step 7a: Patch MachineConfig Ignition Version

```bash
sudo ./07a_patch_machineconfig_ignition_version.sh
```

**Purpose**: Patches ignition version in MachineConfig resources for MCO compatibility.

Machine Config Operator doesn't support 3.6.0-experimental, so this script modifies the ignition version in MachineConfig resources from 3.6.0-experimental to 3.5.0, allowing MCO to start successfully.

---

### Step 7c: Pause Master MCP

```bash
sudo ./07c_pause_master_mcp_incluster.sh
```

**Purpose**: Pauses the master Machine Config Pool to prevent automatic updates during cluster configuration.

---

## Cluster Teardown

### Step 8: Delete Cluster

```bash
sudo ./08_delete_cluster.sh
```

**Purpose**: Destroys all cluster VMs and cleans up resources.

---
## Troubleshooting

### Password-less SSH Issues
If scripts fail with SSH errors:
1. Verify SSH key exists: `ls -la ~/.ssh/id_*.pub`
2. Check kcli VM info: `kcli info vm <vm_name>`
3. Test manual connection: `ssh root@<vm_ip>`
4. Manually copy key if needed: `ssh-copy-id root@<vm_ip>`

### VM Creation Failures
- Check libvirt status: `systemctl status libvirtd`
- Verify libvirt network is active: `virsh net-list`
- Verify base images exist: `ls -lh /var/lib/libvirt/images/*.qcow2`
- Check available disk space: `df -h /var/lib/libvirt/images`
- Check kcli logs: `kcli info vm <vm_name>`

### Network Issues
- Verify libvirt default network is active: `virsh net-list --all`
- Start network if inactive: `virsh net-start default`
- Check HAProxy status: `ssh root@<HAPROXY_VM_IP> "systemctl status haproxy"`
- Verify VIP is configured: `ssh root@<HAPROXY_VM_IP> "ip addr show dev ens3"`
- Test connectivity: `nc -zv 192.168.122.252 6443`

### Bootstrap Hangs
- Check bootstrap logs: `ssh core@192.168.122.56 "journalctl -u bootkube -f"`
- Monitor bootstrap progress: `openshift-install wait-for bootstrap-complete --log-level=debug`
- Check for CNI issues: Run step 5a to remove CNI configuration
- Verify MCC ignition version: Run step 5c to patch ignition version

### Ignition/Attestation Issues
- Verify ignition files exist: `ls -lh *.ign`
- Check ignition version: `jq '.ignition.version' <ignition-file>.ign`
- Verify attestation configuration: `jq '.attestation' <ignition-file>.ign`
- Check TPM state on VM: `ssh core@<vm_ip> "tpm2_getcap properties-fixed"`

### HAProxy Load Balancer Issues
- Verify HAProxy configuration: `ssh root@<HAPROXY_VM_IP> "haproxy -c -f /etc/haproxy/haproxy.cfg"`
- Check backend status: `ssh root@<HAPROXY_VM_IP> "echo 'show stat' | socat stdio /run/haproxy/admin.sock"`
- Review logs: `ssh root@<HAPROXY_VM_IP> "journalctl -u haproxy -f"`

## Additional Resources

- OpenShift Documentation: https://docs.openshift.com
- OKD Documentation: https://docs.okd.io
- Confidential Computing: https://www.redhat.com/en/topics/security/confidential-computing
- Trusted Execution Clusters: https://github.com/trusted-execution-clusters/investigations

## Notes

- All scripts require `sudo` or root privileges
- Scripts are numbered in recommended execution order
- The cluster uses a single control plane node by default (non-HA setup)
