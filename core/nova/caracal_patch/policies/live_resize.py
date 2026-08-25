# Cube downstream: live-resize policy.

from oslo_policy import policy

from nova.policies import base

BASE_POLICY_NAME = 'os_compute_api:servers:live_resize'


live_resize_policies = [
    policy.DocumentedRuleDefault(
        name=BASE_POLICY_NAME,
        check_str=base.ADMIN,
        description="Live resize (vCPU/memory hot-add) a server. "
                    "Cube downstream.",
        operations=[
            {
                'method': 'POST',
                'path': '/servers/{server_id}/action (live-resize)'
            }
        ],
        scope_types=['project']),
]


def list_rules():
    return live_resize_policies
