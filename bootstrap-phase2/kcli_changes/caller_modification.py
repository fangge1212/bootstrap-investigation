"""
Modification for the caller of create_ignition_files()
At line 1607-1608 in /usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py

BEFORE (original):
    create_ignition_files(config, plandir, cluster, domain, api_ip=api_ip, bucket_url=bucket_url,
                          ignition_version=ignition_version)

AFTER (with custom sources support):
"""

# Option A: Hardcoded custom sources
custom_ignition_sources = {
    'master': ['http://127.0.0.1:8001/ignition-clevis-pin-trustee'],
    # 'worker': []  # Optional: add worker custom sources if needed
}

create_ignition_files(config, plandir, cluster, domain, api_ip=api_ip, bucket_url=bucket_url,
                      ignition_version=ignition_version,
                      custom_ignition_sources=custom_ignition_sources)


# Option B: Get from installparam (more configurable)
# First, add custom_ignition_sources to installparam earlier in the code
# Then pass it through:
custom_ignition_sources = installparam.get('custom_ignition_sources', None)

create_ignition_files(config, plandir, cluster, domain, api_ip=api_ip, bucket_url=bucket_url,
                      ignition_version=ignition_version,
                      custom_ignition_sources=custom_ignition_sources)
