from django.conf import settings

# manila_ui ships its own _90_manila_shares.py carrying these two entries. This
# file replaces it rather than sitting beside it -- same filename -- so they have to
# be restated here, or horizon logs "No policy rules for service 'share'" on every
# start. Both paths are relative to POLICY_FILES_PATH, i.e.
# <openstack_dashboard>/conf.
settings.POLICY_FILES.update({
    'share': 'manila_policy.yaml',
})

settings.DEFAULT_POLICY_FILES.update({
    'share': 'default_policies/manila.yaml',
})

# Deliberately narrower than upstream's default, which also lists GlusterFS, HDFS,
# CephFS and MapRFS: config_manila.cpp pins enabled_share_backends to "generic",
# and the generic driver's helpers only serve NFS and CIFS.
OPENSTACK_MANILA_FEATURES = {
    'enable_share_groups': True,
    'enable_replication': True,
    'enable_migration': True,
    'enable_public_share_type_creation': True,
    'enable_public_share_group_type_creation': True,
    'enable_public_shares': True,
    'enabled_share_protocols': ['NFS', 'CIFS'],
}
