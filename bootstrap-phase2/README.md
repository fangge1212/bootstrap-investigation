# OpenShift Confidential Cluster Bootstrap Guide

This guide helps you create an OpenShift confidential cluster using the provided automation scripts.

## Prerequisites

- RHEL/CentOS host with KVM/libvirt installed
- **kcli** tool installed and configured
  - Used to create and manage cluster VMs
  - Verify installation: `kcli list vms`
  - Ensure default libvirt connection is working
- SSH key pair generated (`~/.ssh/id_rsa.pub` or `~/.ssh/id_ed25519.pub`)
- OpenShift installer binary (`openshift-install`) with node attestation support
  - Build it from https://github.com/fangge1212/openshift-installer/tree/confidential_cluster_config
- `oc` CLI tool for image inspection
- `just` command runner (for building CoreOS image)
- **External Trustee Server** - Required for confidential computing attestation
  - Must be accessible from the cluster nodes
- Required base images:
  - CentOS Stream CoreOS(used as base vm image for cluster node): `/var/lib/libvirt/images/centos-stream-coreos-10.0.20251113-0-qemu.x86_64.qcow2`
    - See [Building CentOS Stream CoreOS](#building-centos-stream-coreos) section below for build instructions

## Building CentOS Stream CoreOS

The CentOS Stream CoreOS (SCOS) image with remote attestation support is built following the instructions from [trusted-execution-clusters/investigations/coreos](https://github.com/trusted-execution-clusters/investigations/tree/main/coreos).

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

The `trustee-clevis-pin.json` file contains the Clevis pin configuration for disk encryption with Trustee attestation. This file is passed to `openshift-install` as an environment variable during cluster creation.

This file configures:
- **Attestation Key Registration URL**: The Trustee server endpoint for attestation key registration (e.g., `http://10.73.211.28:9001/register-ak`)
- **Remote Ignition URL**: The URL where ignition configurations can be fetched remotely

**Important**: Update the attestation and ignition URLs in `trustee-clevis-pin.json` to match your Trustee server before creating the cluster.

**Note**: The attestation key registration URL is also configured in:
- `04_restart_ctlplane.sh` - For control plane node attestation

If you change the Trustee server URL, update it in both locations.

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

### Step 2: Remove CNI from Bootstrap

```bash
sudo ./02_rm_cni_bootstrap.sh
```

**Purpose**: Removes CNI configuration from the bootstrap node to workaround a bug in the SCOS image.

---

### Step 3: Patch MCC Ignition Version

```bash
sudo ./03_patch_mcc_ignition_version.sh
```

**Purpose**: Patches the Machine Config Controller ignition version for compatibility.

Machine Config Operator doesn't support ignition version 3.6.0, so this script modifies the ignition version in MCC bootstrap manifests from 3.6.0 to 3.5.0, preventing MCC bootstrap failures.

---

### Step 4: Restart Control Plane

```bash
sudo ./04_restart_ctlplane.sh
```

**Purpose**: Recreates the control plane VM with updated ignition configuration and attestation support.

This script:
- Destroys the control plane VM
- Backs up the original ignition file
- Updates ignition version to 3.6.0
- Adds attestation configuration:
  - Configures attestation key registration URL (default: `http://10.73.211.28:9001/register-ak`)
  - Update the URL in the script if using a different Trustee server
- Cleans up TPM state and storage
- Recreates the control plane VM

---

### Step 5: Restart Worker

```bash
sudo ./05_restart_worker.sh
```

**Purpose**: Recreates the worker VM with updated ignition configuration and attestation support.

---

### Step 6: Patch MachineConfig Ignition Version

```bash
sudo ./06_patch_machineconfig_ignition_version.sh
```

**Purpose**: Patches ignition version in MachineConfig resources for MCO compatibility.

Machine Config Operator doesn't support 3.6.0, so this script modifies the ignition version in MachineConfig resources from 3.6.0 to 3.5.0, allowing MCO to start successfully.

---

### Step 7: Pause Master MCP

```bash
sudo ./07_pause_master_mcp_incluster.sh
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

### Step 9: Cleanup Operator Resources

```bash
sudo ./09_cleanup_operator_resources.sh
```

**Purpose**: Cleans up operator-related resources after cluster deletion.

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

### Bootstrap Hangs
- Check bootstrap logs: `ssh core@192.168.122.56 "journalctl -u bootkube -f"`
- Monitor bootstrap progress: `openshift-install wait-for bootstrap-complete --log-level=debug`
- Check for CNI issues: Run step 2 to remove CNI configuration
- Verify MCC ignition version: Run step 3 to patch ignition version
- Check the failed containers on bootstrap node and their logs: `sudo crictl ps -a`, `sudo crictl logs <CONTAINER_ID>`

### Ignition/Attestation Issues
- Verify ignition files exist: `ls -lh *.ign`
- Check ignition version: `jq '.ignition.version' <ignition-file>.ign`
- Verify attestation configuration: `jq '.attestation' <ignition-file>.ign`
- Check TPM state on VM: `ssh core@<vm_ip> "tpm2_getcap properties-fixed"`

## Additional Resources

- OpenShift Documentation: https://docs.openshift.com
- OKD Documentation: https://docs.okd.io
- Confidential Computing: https://www.redhat.com/en/topics/security/confidential-computing
- Trusted Execution Clusters: https://github.com/trusted-execution-clusters/investigations

## Notes

- All scripts require `sudo` or root privileges
- Scripts are numbered in recommended execution order
- The cluster uses a single control plane node by default (non-HA setup)
