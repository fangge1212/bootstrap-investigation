"""
Modified create_ignition_files() function that auto-preserves custom sources from .ori files
Replace the function at line 137 in /usr/lib/python3.12/site-packages/kvirt/cluster/openshift/__init__.py
"""
import json
import os


def create_ignition_files(config, plandir, cluster, domain, api_ip=None, bucket_url=None, ignition_version=None):
    """
    Create ignition files and automatically preserve custom sources from .ori files

    This function reads master.ign.ori and worker.ign.ori to extract any custom
    ignition sources (beyond the first default source) and includes them in the
    regenerated ignition files.
    """
    clusterdir = os.path.expanduser(f"~/.kcli/clusters/{cluster}")

    def extract_custom_sources(ori_file_path):
        """
        Extract custom ignition sources from .ori file

        Args:
            ori_file_path: Path to the .ori ignition file

        Returns:
            List of custom source URLs (excluding the first default source)
        """
        custom_sources = []
        if os.path.exists(ori_file_path):
            try:
                with open(ori_file_path, 'r') as f:
                    data = json.load(f)
                    merge_list = data.get('ignition', {}).get('config', {}).get('merge', [])

                    # Skip the first source (it's the default OpenShift source that kcli replaces)
                    # Extract any additional custom sources
                    if len(merge_list) > 1:
                        for source_entry in merge_list[1:]:
                            if 'source' in source_entry:
                                custom_sources.append(source_entry['source'])
            except (json.JSONDecodeError, KeyError, IOError) as e:
                # If file doesn't exist or is malformed, just continue with no custom sources
                pass

        return custom_sources

    # Extract custom sources from master.ign.ori
    master_custom_sources = extract_custom_sources(f"{clusterdir}/master.ign.ori")

    # Create master/ctlplane ignition with custom sources
    ignition_overrides = {
        'api_ip': api_ip,
        'cluster': cluster,
        'domain': domain,
        'role': 'master',
        'custom_sources': master_custom_sources
    }
    ctlplane_ignition = config.process_inputfile(cluster, f"{plandir}/ignition.j2", overrides=ignition_overrides)
    with open(f"{clusterdir}/ctlplane.ign", 'w') as f:
        f.write(ctlplane_ignition)

    # Extract custom sources from worker.ign.ori
    worker_custom_sources = extract_custom_sources(f"{clusterdir}/worker.ign.ori")

    # Create worker ignition with custom sources
    del ignition_overrides['role']
    ignition_overrides['custom_sources'] = worker_custom_sources
    worker_ignition = config.process_inputfile(cluster, f"{plandir}/ignition.j2", overrides=ignition_overrides)
    with open(f"{clusterdir}/worker.ign", 'w') as f:
        f.write(worker_ignition)

    # Create bootstrap ignition if needed
    if bucket_url is not None:
        if config.type == 'openstack':
            ignition_overrides['ca_file'] = config.k.ca_file
        ignition_overrides['bucket_url'] = bucket_url
        # Note: bootstrap typically doesn't need custom sources, but you could
        # extract from bootstrap.ign.ori if needed
        bootstrap_ignition = config.process_inputfile(cluster, f"{plandir}/ignition.j2", overrides=ignition_overrides)
        with open(f"{clusterdir}/bootstrap.ign", 'w') as f:
            f.write(bootstrap_ignition)
