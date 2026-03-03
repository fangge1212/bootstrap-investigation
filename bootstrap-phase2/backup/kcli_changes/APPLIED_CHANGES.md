# Applied Changes Summary

## Date: 2026-01-26

## Changes Applied

### ✅ 1. Backed up original files
- `/usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py.backup`
- `/usr/lib/python3.12/site-packages/kvirt/cluster/openshift/ignition.j2.backup`

### ✅ 2. Modified ignition.j2 template
**File:** `/usr/lib/python3.12/site-packages/kvirt/cluster/openshift/ignition.j2`

**Change:** Added support for custom_sources variable to append additional ignition sources:
```jinja2
{% if custom_sources is defined and custom_sources|length > 0 %}
  {% for src in custom_sources %},
  {
    "source": "{{ src }}"
  }{% endfor %}
{% endif %}
```

### ✅ 3. Modified create_ignition_files() function
**File:** `/usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py`
**Lines:** 137-212 (function expanded from 17 lines to 76 lines)

**Changes:**
- Added `extract_custom_sources()` helper function
- Reads `master.ign.ori`, `worker.ign.ori`, and `bootstrap.ign.ori` files
- Extracts custom ignition sources (skipping the first default source)
- Passes custom sources to the template via `ignition_overrides`
- Now always regenerates bootstrap.ign with custom sources (previously only for cloud providers)

### ✅ 4. Added bootstrap.ign preservation
**File:** `/usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py`
**Line:** 1661

**Change:** Added move operation to preserve original bootstrap.ign:
```python
move(f"{clusterdir}/bootstrap.ign", f"{clusterdir}/bootstrap.ign.ori")
```

This ensures bootstrap.ign is backed up and regenerated with custom sources, just like master.ign and worker.ign.

## How It Works

### Before (Original Behavior):
```
openshift-install → creates master.ign with multiple sources
kcli → renames to master.ign.ori
kcli → regenerates ctlplane.ign with only kcli's source
Result: Custom sources lost ❌
```

### After (New Behavior):
```
openshift-install → creates master.ign with multiple sources
kcli → renames to master.ign.ori
kcli → reads master.ign.ori, extracts custom sources
kcli → regenerates ctlplane.ign with kcli's source + custom sources
Result: Custom sources preserved ✅
```

## Test Results

Tested extraction logic with existing `master.ign.ori`:
```
All sources in master.ign.ori:
  [0] https://api-int.test.confidential-cluster.org:22623/config/master
  [1] http://127.0.0.1:8001/ignition-clevis-pin-trustee

Extracted custom sources (skipping first):
  - http://127.0.0.1:8001/ignition-clevis-pin-trustee

✓ These custom sources will be preserved in ctlplane.ign!
```

## Next Steps

The next time you run `kcli create cluster openshift`, the modified code will:
1. Automatically read custom sources from `master.ign.ori`, `worker.ign.ori`, and `bootstrap.ign.ori`
2. Include them in the regenerated `ctlplane.ign`, `worker.ign`, and `bootstrap.ign` files

## Verification

After creating a new cluster, verify custom sources are preserved:

```bash
# View all .ori files (should all exist)
ls -la /root/.kcli/clusters/YOUR_CLUSTER/*.ori

# View original sources from all three .ori files
jq '.ignition.config.merge' /root/.kcli/clusters/YOUR_CLUSTER/master.ign.ori
jq '.ignition.config.merge' /root/.kcli/clusters/YOUR_CLUSTER/worker.ign.ori
jq '.ignition.config.merge' /root/.kcli/clusters/YOUR_CLUSTER/bootstrap.ign.ori

# View regenerated sources (should all have custom sources)
jq '.ignition.config.merge' /root/.kcli/clusters/YOUR_CLUSTER/ctlplane.ign
jq '.ignition.config.merge' /root/.kcli/clusters/YOUR_CLUSTER/worker.ign
jq '.ignition.config.merge' /root/.kcli/clusters/YOUR_CLUSTER/bootstrap.ign
```

Expected result in all regenerated files (ctlplane.ign, worker.ign, bootstrap.ign):
```json
[
  {
    "source": "http://api-ip:22624/config/master"
  },
  {
    "source": "http://127.0.0.1:8001/ignition-clevis-pin-trustee"
  }
]
```

## Rollback (if needed)

To revert to original kcli code:
```bash
sudo cp /usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py.backup \
        /usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py

sudo cp /usr/lib/python3.12/site-packages/kvirt/cluster/openshift/ignition.j2.backup \
        /usr/lib/python3.12/site-packages/kvirt/cluster/openshift/ignition.j2
```

## Files Created in This Session

- `create_ignition_files_auto_preserve.py` - Modified function code
- `ignition.j2.patch` - Modified template
- `IMPLEMENTATION_STEPS.md` - Implementation guide
- `SUMMARY.md` - Solution overview
- `test_extraction.py` - Test script for master/worker
- `verify_bootstrap_changes.sh` - Verification script for bootstrap changes
- `BOOTSTRAP_FIX.md` - Detailed bootstrap.ign fix documentation
- `APPLIED_CHANGES.md` - This file (complete summary)

## Benefits

✅ **Complete** - All three ignition files (bootstrap, master, worker) preserve custom sources
✅ **Automatic** - No manual configuration needed
✅ **Backward compatible** - Works even if .ori files don't exist
✅ **Clean** - No hardcoded URLs in kcli source
✅ **Flexible** - Works with any custom sources from openshift-install
✅ **Role-specific** - Bootstrap, master, and worker can each have different custom sources
✅ **Consistent** - All three ignition types handled identically
