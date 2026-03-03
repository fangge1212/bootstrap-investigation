# Bootstrap.ign Custom Sources Fix

## Problem

The bootstrap.ign file was not preserving custom ignition sources from openshift-install because:

1. **bootstrap.ign was never moved to .ori** - Unlike master.ign and worker.ign, bootstrap.ign was not backed up
2. **bootstrap.ign was only regenerated for cloud providers** - It was only regenerated when `bucket_url` was set
3. **No custom source extraction for bootstrap** - Even when regenerated, custom sources were not extracted or applied

## Solution Applied

### Change 1: Move bootstrap.ign to .ori (Line 1661)
**File:** `/usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py`

Added line to preserve the original bootstrap.ign:
```python
move(f"{clusterdir}/master.ign", f"{clusterdir}/master.ign.ori")
move(f"{clusterdir}/worker.ign", f"{clusterdir}/worker.ign.ori")
move(f"{clusterdir}/bootstrap.ign", f"{clusterdir}/bootstrap.ign.ori")  # NEW
```

### Change 2: Extract custom sources from bootstrap.ign.ori (Lines 201-202)
**File:** `/usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py`

Added extraction logic in `create_ignition_files()`:
```python
# Extract custom sources from bootstrap.ign.ori
bootstrap_custom_sources = extract_custom_sources(f"{clusterdir}/bootstrap.ign.ori")
```

### Change 3: Always regenerate bootstrap.ign with custom sources (Lines 204-212)
**File:** `/usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py`

Modified the bootstrap regeneration to:
- Always regenerate bootstrap.ign (not just for cloud providers)
- Include custom sources in the regenerated file

```python
# Create bootstrap ignition with custom sources
if bucket_url is not None:
    if config.type == 'openstack':
        ignition_overrides['ca_file'] = config.k.ca_file
    ignition_overrides['bucket_url'] = bucket_url
ignition_overrides['custom_sources'] = bootstrap_custom_sources
bootstrap_ignition = config.process_inputfile(cluster, f"{plandir}/ignition.j2", overrides=ignition_overrides)
with open(f"{clusterdir}/bootstrap.ign", 'w') as f:
    f.write(bootstrap_ignition)
```

## Behavior Comparison

### Before Fix:

```
openshift-install creates bootstrap.ign with:
  - Default source
  - Custom source (Clevis/Trustee)

kcli workflow:
  1. Uploads bootstrap.ign to bucket (if cloud) ✓
  2. Does NOT move to .ori ✗
  3. Only regenerates for cloud providers ✗
  4. Overwrites original without custom sources ✗

Result: bootstrap.ign missing custom sources ✗
```

### After Fix:

```
openshift-install creates bootstrap.ign with:
  - Default source
  - Custom source (Clevis/Trustee)

kcli workflow:
  1. Uploads bootstrap.ign to bucket (if cloud) ✓
  2. Moves to bootstrap.ign.ori ✓
  3. Extracts custom sources from .ori ✓
  4. Always regenerates with custom sources ✓

Result: bootstrap.ign preserves custom sources ✓
```

## Files Modified

1. `/usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py`
   - Line 1661: Added move for bootstrap.ign
   - Line 202: Added custom source extraction
   - Lines 204-212: Modified bootstrap regeneration logic

## Expected Result

After the next cluster deployment, you should see:

```bash
# All three .ori files will exist
ls -la /root/.kcli/clusters/YOUR_CLUSTER/*.ori
-rw-r-----. 1 root root bootstrap.ign.ori
-rw-r-----. 1 root root master.ign.ori
-rw-r-----. 1 root root worker.ign.ori

# bootstrap.ign will contain custom sources
jq '.ignition.config.merge' /root/.kcli/clusters/YOUR_CLUSTER/bootstrap.ign
[
  {
    "source": "http://api-ip:22624/config/..."
  },
  {
    "source": "http://127.0.0.1:8001/ignition-clevis-pin-trustee"
  }
]
```

## Verification

To verify the fix is working:

```bash
# After creating a new cluster, check all three files
for file in bootstrap master worker; do
  echo "=== ${file}.ign.ori ==="
  jq '.ignition.config.merge' /root/.kcli/clusters/YOUR_CLUSTER/${file}.ign.ori
  echo ""
done

for file in bootstrap ctlplane worker; do
  echo "=== ${file}.ign ==="
  jq '.ignition.config.merge' /root/.kcli/clusters/YOUR_CLUSTER/${file}.ign
  echo ""
done
```

All files should show both the default source AND your custom Clevis/Trustee source.

## Benefits

✅ **Consistent handling** - bootstrap.ign now handled the same as master/worker
✅ **Always preserved** - Custom sources always preserved, not just for cloud providers
✅ **Automatic** - No manual configuration needed
✅ **Complete solution** - All three ignition files (bootstrap, master, worker) preserve custom sources
