06_pause_master_mcp_incluster.sh# OpenShift Confidential Cluster Bootstrap Guide

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

   Update the following variables in the [justfile](https://github.com/trusted-execution-clusters/investigations/blob/main/coreos/justfile#L3):

   ```makefile
   # Replace with the image SHA obtained from step 2
   scos_base_img := "quay.io/okd/scos-content@sha256:0c00cdfc08c157bba474f9f0e40870782bed71e86a03f883227ed1c79def531e"

   # Required trustee and clevis images
   kbc_image := "quay.io/trusted-execution-clusters/trustee-attester:centos-stream-standard-v0.17.0"
   clevis_pin_trustee_image := "quay.io/trusted-execution-clusters/clevis-pin-trustee:centos-stream-75015a5"
   ignition_image := "quay.io/trusted-execution-clusters/ignition:centos-stream-5a45ee84"
   ```

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

The `manifests/` directory contains custom MachineConfig and other resources that will be applied during cluster installation. You need to create this directory and MachineConfig files for master and worker nodes that reference your custom SCOS container image.

**Creating the Manifest Directory and Files:**

1. **Create the manifest directory** (if it doesn't exist):
   ```bash
   mkdir -p manifests
   ```

2. **Create MachineConfig for master nodes** (`manifests/99-master-custom-os.yaml`):
   ```yaml
   apiVersion: machineconfiguration.openshift.io/v1
   kind: MachineConfig
   metadata:
     labels:
       machineconfiguration.openshift.io/role: master
     name: 99-master-custom-os
   spec:
     osImageURL: quay.io/<your-username>/scos@sha256:<SHA256_VALUE>
   ```

3. **Create MachineConfig for worker nodes** (`manifests/99-worker-custom-os.yaml`):
   ```yaml
   apiVersion: machineconfiguration.openshift.io/v1
   kind: MachineConfig
   metadata:
     labels:
       machineconfiguration.openshift.io/role: worker
     name: 99-worker-custom-os
   spec:
     osImageURL: quay.io/<your-username>/scos@sha256:<SHA256_VALUE>
   ```

**Important**:
- Replace `<your-username>` with your quay.io username
- Replace `<SHA256_VALUE>` with the actual SHA256 digest of your SCOS image
- The `osImageURL` must point to the custom SCOS container image you built and pushed to quay.io in the [Building CentOS Stream CoreOS](#building-centos-stream-coreos) section
- These MachineConfigs ensure that both master and worker nodes use your custom SCOS image with confidential computing support

To get the correct manifest digest (the one shown on quay.io):
```bash
# Method 1: Get it from the push output
# The digest is shown when you run: podman push quay.io/<your-username>/scos:4.21.0-okd-scos.ec.11

# Method 2: Use skopeo to inspect the remote image
skopeo inspect docker://quay.io/<your-username>/scos:4.21.0-okd-scos.ec.11 | jq -r '.Digest'

# Method 3: Pull by tag and check the digest
podman pull quay.io/<your-username>/scos:4.21.0-okd-scos.ec.11
podman inspect quay.io/<your-username>/scos:4.21.0-okd-scos.ec.11 | jq -r '.[0].Digest'
```

**Note**: The manifest digest shown on quay.io web interface (under "Fetch Tag" → "Podman Pull by Digest") is the correct value to use. This is the digest of the manifest, not the local image digest.

#### Run Cluster Creation

```bash
sudo ./01_create_cluster.sh
```

This script:
- Sets up environment variables for confidential cluster configuration
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

**Purpose**: Patches the Machine Config Controller ignition version for compatibility on the bootstrap node.

The current MCO doesn't support ignition version 3.6.0-experimental. This script:
- SSHes into the bootstrap node
- Modifies the ignition version in MCC bootstrap manifests from 3.6.0-experimental to 3.5.0
- Patches the following files in `/etc/mcc/bootstrap/`:
  - `99_openshift-machineconfig_99-worker-ssh.yaml`
  - `99_openshift-installer-ignition_master.yaml`
  - `99_openshift-machineconfig_99-master-ssh.yaml`
  - `99_openshift-installer-ignition_worker.yaml`

This prevents MCC from failing during bootstrap when it encounters the unsupported ignition version.

---

### Step 4: Restart Control Plane

```bash
sudo ./04_restart_ctlplane.sh
```

**Purpose**: Recreates the control plane VM with updated ignition configuration and attestation support.

**Background**: kcli hardcodes the ignition version to 3.2.0 and overrides the merge source configuration. The original `master.ign` generated by openshift-install can be found at `/root/.kcli/clusters/test/master.ign.ori` for comparison.

This script:
- Stops the control plane VM
- Backs up the original ignition file
- Updates ignition version from 3.2.0 to 3.6.0-experimental
- Adds the ignition merge source: `http://10.73.211.28:8000/ignition-clevis-pin-trustee`
  - This restores the Clevis/Trustee configuration that kcli removed
  - Update the URL if using a different Trustee server
- Cleans up TPM state and disk image
- Recreates the control plane VM with the corrected configuration

The script provides detailed output at each step to track progress.

---

### Step 5: Patch MachineConfig Ignition Version

```bash
sudo ./05_patch_machineconfig_ignition_version.sh
```

**Purpose**: Patches ignition version in MachineConfig cluster resources for MCO compatibility.

**Why both Step 3 and Step 6?**
- **Step 3** patches MCC manifest files on the bootstrap node's filesystem during the bootstrap phase
- **Step 6** patches the actual MachineConfig objects in the Kubernetes cluster after the API server is up

Even though Step 3 patches the source manifests, the resulting MachineConfig objects in the cluster may still have 3.6.0-experimental (from installer defaults), causing MCO to fail with:
```
Failed to render configuration: unknown version. Supported spec versions: 2.2,3.0,3.1,3.2,3.3,3.4,3.5
```

This script:
- Waits for the API server to be accessible
- Waits for MachineConfig objects to exist
- Patches the following MachineConfigs from 3.6.0-experimental to 3.5.0:
  - `99-installer-ignition-master`
  - `99-installer-ignition-worker`
  - `99-master-ssh`
  - `99-worker-ssh`
- Verifies the changes

This ensures MCO can successfully render configurations for both master and worker pools.

---

### Step 6: Pause Master MCP

```bash
sudo ./06_pause_master_mcp_incluster.sh
```

**Purpose**: Prevents the master nodes from upgrading to the released configuration without trustee support.

By pausing the master MachineConfigPool, we ensure that:
- Masters retain the custom ignition configuration with Clevis/Trustee integration
- Masters don't switch to the default released configuration that lacks trustee support
- The confidential computing attestation setup is preserved

This script:
- Waits for the API server to be accessible
- Waits for the master MachineConfigPool to be created
- Checks the current pause status
- Sets `spec.paused: true` on the master MachineConfigPool
- Verifies the change was successful

**Note**: This prevents normal MachineConfig updates, but does NOT prevent the initial bootstrap pivot during first boot.

---

### Step 7: Restart Worker

```bash
sudo ./07_restart_worker.sh
```

**Purpose**: Recreates the worker VM with updated ignition configuration and attestation support.

**Background**: Similar to the control plane, kcli hardcodes the ignition version to 3.2.0 and overrides the merge source configuration. The original `worker.ign` generated by openshift-install can be found at `/root/.kcli/clusters/test/worker.ign.ori` for comparison.

This script:
- Stops the worker VM
- Backs up the original ignition file
- Updates ignition version from 3.2.0 to 3.6.0-experimental
- Adds the ignition merge source: `http://10.73.211.28:8000/ignition-clevis-pin-trustee`
  - This restores the Clevis/Trustee configuration that kcli removed
  - Update the URL if using a different Trustee server
- Cleans up TPM state and disk image
- Recreates the worker VM with the corrected configuration

The script provides detailed output at each step to track progress.

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
