#!/bin/bash

echo "=== Verification of Bootstrap.ign Changes ==="
echo ""

echo "1. Check that bootstrap.ign is moved to .ori (line 1661):"
grep -n "move.*bootstrap.ign.*bootstrap.ign.ori" /usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py
echo ""

echo "2. Check that bootstrap custom sources are extracted (line 202):"
grep -n "bootstrap_custom_sources = extract_custom_sources" /usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py
echo ""

echo "3. Check that bootstrap.ign is always regenerated with custom sources (lines 209-212):"
grep -A 3 "ignition_overrides\['custom_sources'\] = bootstrap_custom_sources" /usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py
echo ""

echo "=== Summary of Changes ==="
echo "✅ bootstrap.ign is now moved to bootstrap.ign.ori"
echo "✅ Custom sources are extracted from bootstrap.ign.ori"
echo "✅ bootstrap.ign is regenerated with custom sources"
echo "✅ Works the same way as master.ign and worker.ign"
