#!/bin/bash
# Quick verification script to check if custom sources are preserved
# Run this after creating a new cluster with kcli

CLUSTER_NAME="${1:-test}"
CLUSTER_DIR="/root/.kcli/clusters/${CLUSTER_NAME}"

echo "════════════════════════════════════════════════════════════"
echo "  Custom Ignition Sources Verification"
echo "  Cluster: ${CLUSTER_NAME}"
echo "════════════════════════════════════════════════════════════"
echo ""

if [ ! -d "$CLUSTER_DIR" ]; then
    echo "❌ Cluster directory not found: $CLUSTER_DIR"
    echo "Usage: $0 [cluster-name]"
    exit 1
fi

echo "1. Checking .ori files exist..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for file in bootstrap.ign.ori master.ign.ori worker.ign.ori; do
    if [ -f "$CLUSTER_DIR/$file" ]; then
        echo "✅ $file exists"
    else
        echo "❌ $file NOT FOUND"
    fi
done
echo ""

echo "2. Checking original sources in .ori files..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for file in bootstrap master worker; do
    echo "--- $file.ign.ori ---"
    if [ -f "$CLUSTER_DIR/${file}.ign.ori" ]; then
        jq -r '.ignition.config.merge[]?.source // "No sources found"' "$CLUSTER_DIR/${file}.ign.ori" 2>/dev/null | sed 's/^/  /'
    fi
    echo ""
done

echo "3. Checking regenerated ignition files have custom sources..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for file in bootstrap ctlplane worker; do
    echo "--- $file.ign ---"
    if [ -f "$CLUSTER_DIR/${file}.ign" ]; then
        sources=$(jq -r '.ignition.config.merge[]?.source // empty' "$CLUSTER_DIR/${file}.ign" 2>/dev/null)
        if [ -z "$sources" ]; then
            echo "  ⚠️  No sources found (file might have different structure)"
        else
            echo "$sources" | while read -r src; do
                if [[ "$src" == *"ignition-clevis-pin-trustee"* ]] || [[ "$src" == *"127.0.0.1:8001"* ]]; then
                    echo "  ✅ $src (CUSTOM SOURCE PRESERVED!)"
                else
                    echo "  ℹ️  $src"
                fi
            done
        fi
    else
        echo "  ❌ File not found"
    fi
    echo ""
done

echo "════════════════════════════════════════════════════════════"
echo "Verification complete!"
echo ""
echo "Expected result: All three files (bootstrap, ctlplane, worker)"
echo "should contain the custom Clevis/Trustee source."
echo "════════════════════════════════════════════════════════════"
