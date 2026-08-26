# Cube downstream: resize plan -- the capability envelope an operator-facing
# resize dialog needs to decide LIVE vs COLD for every candidate flavor.
#
# Deliberately returns the INSTANCE's envelope once rather than a verdict per
# flavor: the caller evaluates candidates locally. A per-flavor endpoint would
# cost a round-trip each (~46ms measured) times the size of the flavor list,
# every time the dialog opens. See spike cubecos#1366.

from nova.api.openstack import common
from nova.api.openstack import wsgi
from nova.compute import api as compute
from nova.compute import utils as compute_utils
from nova import cube_live_resize as clr
from nova.policies import live_resize as lr_policies


class ResizePlanController(wsgi.Controller):
    def __init__(self):
        super(ResizePlanController, self).__init__()
        self.compute_api = compute.API()

    @wsgi.expected_errors((403, 404))
    def index(self, req, server_id):
        context = req.environ['nova.context']
        instance = common.get_instance(self.compute_api, context, server_id)
        context.can(lr_policies.BASE_POLICY_NAME,
                    target={'project_id': instance.project_id})

        flavor = instance.flavor
        recorded = clr.recorded_headroom(instance)
        if recorded is None:
            # booted before the ceiling was recorded; the config-derived value
            # is an estimate and is wrong when the flavor carried an override
            max_vcpus, max_mem_mb = clr.headroom(flavor)
            exact = False
        else:
            max_vcpus, max_mem_mb = recorded
            exact = True

        # same helper _lr_validate uses, so the plan and the action agree
        is_bfv = compute_utils.is_volume_backed_instance(context, instance)

        return {
            'resize_plan': {
                'max_vcpus': max_vcpus,
                'max_memory_mb': max_mem_mb,
                'ceiling_is_exact': exact,
                'boot_from_volume': is_bfv,
                'blocked_by_spec': clr.blocked(flavor),
                'current': {
                    'vcpus': flavor.vcpus,
                    'memory_mb': flavor.memory_mb,
                    'root_gb': flavor.root_gb,
                    'ephemeral_gb': flavor.ephemeral_gb,
                },
            },
        }
