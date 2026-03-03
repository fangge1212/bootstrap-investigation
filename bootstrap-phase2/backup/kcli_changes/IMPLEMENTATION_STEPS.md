# Implementation Steps: Auto-Preserve Custom Ignition Sources

## Overview
This solution automatically preserves custom ignition sources from the original `master.ign.ori` and `worker.ign.ori` files when kcli regenerates ignition files.

## What Gets Modified

### 1. The `create_ignition_files()` function
**File:** `/usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py`
**Lines:** 137-153

**What it does:**
- Reads `master.ign.ori` and `worker.ign.ori`
- Extracts custom sources (any sources beyond the first one)
- Passes them to the template
- No caller changes needed - function signature stays the same!

### 2. The ignition template
**File:** `/usr/lib/python3.12/site-packages/kvirt/cluster/openshift/ignition.j2`

**What it does:**
- Appends custom sources after the default kcli source

## Implementation

### Step 1: Backup Original Files
```bash
sudo cp /usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py \
        /usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py.backup

sudo cp /usr/lib/python3.12/site-packages/kvirt/cluster/openshift/ignition.j2 \
        /usr/lib/python3.12/site-packages/kvirt/cluster/openshift/ignition.j2.backup
```

### Step 2: Update the Template
```bash
sudo cp ignition.j2.patch /usr/lib/python3.12/site-packages/kvirt/cluster/openshift/ignition.j2
```

### Step 3: Update the Function
Edit `/usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py`:

**Replace lines 137-153** (the entire `create_ignition_files()` function) with the code from `create_ignition_files_auto_preserve.py`

### Step 4: Verify
After installation, check that custom sources are preserved:

```bash
# View master.ign.ori (original with custom sources)
jq '.ignition.config.merge' /root/.kcli/clusters/test/master.ign.ori

# View ctlplane.ign (regenerated, should now have custom sources)
jq '.ignition.config.merge' /root/.kcli/clusters/test/ctlplane.ign
```

## How It Works

**Before modification:**
```
openshift-install creates master.ign with sources:
  1. http://api:22623/config/master (default)
  2. http://127.0.0.1:8001/ignition-clevis-pin-trustee (your custom)

kcli renames to master.ign.ori
kcli regenerates ctlplane.ign with only:
  1. http://api:22624/config/master (kcli's source)

❌ Custom source lost!
```

**After modification:**
```
openshift-install creates master.ign with sources:
  1. http://api:22623/config/master (default)
  2. http://127.0.0.1:8001/ignition-clevis-pin-trustee (your custom)

kcli renames to master.ign.ori
kcli reads master.ign.ori, extracts custom sources
kcli regenerates ctlplane.ign with:
  1. http://api:22624/config/master (kcli's source)
  2. http://127.0.0.1:8001/ignition-clevis-pin-trustee (preserved!)

✅ Custom source preserved!
```

## Benefits

✅ **Automatic** - No manual configuration needed
✅ **Clean** - No hardcoded URLs in kcli code
✅ **Flexible** - Works with any custom sources from openshift-install
✅ **Backward compatible** - Works fine if no .ori files exist
✅ **Role-specific** - Master and worker can have different custom sources

## Testing

Create a test cluster:
```bash
kcli create cluster openshift --pf your-plan.yml test-cluster
```

Verify the custom source appears in both files:
```bash
echo "=== Original master.ign.ori ==="
jq '.ignition.config.merge' /root/.kcli/clusters/test-cluster/master.ign.ori

echo -e "\n=== Regenerated ctlplane.ign ==="
jq '.ignition.config.merge' /root/.kcli/clusters/test-cluster/ctlplane.ign
```

Both should show your custom source!
