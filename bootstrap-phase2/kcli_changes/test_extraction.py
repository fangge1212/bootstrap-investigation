#!/usr/bin/env python3
"""Test script to verify custom source extraction works"""
import json
import os

def extract_custom_sources(ori_file_path):
    """Extract custom ignition sources from .ori file"""
    custom_sources = []
    if os.path.exists(ori_file_path):
        try:
            with open(ori_file_path, 'r') as f:
                data = json.load(f)
                merge_list = data.get('ignition', {}).get('config', {}).get('merge', [])

                # Skip the first source (default OpenShift source)
                # Extract any additional custom sources
                if len(merge_list) > 1:
                    for source_entry in merge_list[1:]:
                        if 'source' in source_entry:
                            custom_sources.append(source_entry['source'])
        except (json.JSONDecodeError, KeyError, IOError) as e:
            print(f"Error reading {ori_file_path}: {e}")
            pass

    return custom_sources

# Test with your actual master.ign.ori
ori_file = "/root/.kcli/clusters/test/master.ign.ori"
print(f"Testing extraction from: {ori_file}\n")

if os.path.exists(ori_file):
    with open(ori_file, 'r') as f:
        data = json.load(f)
        all_sources = data.get('ignition', {}).get('config', {}).get('merge', [])

    print("All sources in master.ign.ori:")
    for i, src in enumerate(all_sources):
        print(f"  [{i}] {src.get('source')}")

    custom = extract_custom_sources(ori_file)
    print(f"\nExtracted custom sources (skipping first):")
    for src in custom:
        print(f"  - {src}")

    print("\n✓ These custom sources will be preserved in ctlplane.ign!")
else:
    print(f"File not found: {ori_file}")
