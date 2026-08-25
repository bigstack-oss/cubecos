# Cube downstream: live-resize server action (vCPU/memory hot-add).

from webob import exc

from nova.api.openstack import common
from nova.api.openstack import wsgi
from nova.api import validation
from nova.compute import api as compute
from nova import exception
from nova.policies import live_resize as lr_policies

live_resize_schema = {
    'type': 'object',
    'properties': {
        'live-resize': {
            'type': 'object',
            'properties': {
                'flavorRef': {'type': ['string', 'integer'],
                              'minLength': 1},
            },
            'required': ['flavorRef'],
            'additionalProperties': False,
        },
    },
    'required': ['live-resize'],
    'additionalProperties': False,
}


class LiveResizeController(wsgi.Controller):
    def __init__(self):
        super(LiveResizeController, self).__init__()
        self.compute_api = compute.API()

    @wsgi.response(202)
    @wsgi.expected_errors((400, 403, 404, 409))
    @wsgi.action('live-resize')
    @validation.schema(live_resize_schema)
    def _live_resize(self, req, id, body):
        context = req.environ['nova.context']
        instance = common.get_instance(self.compute_api, context, id)
        context.can(lr_policies.BASE_POLICY_NAME,
                    target={'project_id': instance.project_id})
        flavor_ref = str(body['live-resize']['flavorRef'])
        try:
            self.compute_api.live_resize(context, instance, flavor_ref)
        except exception.FlavorNotFound as e:
            raise exc.HTTPBadRequest(explanation=e.format_message())
        except exception.LiveResizeError as e:
            raise exc.HTTPBadRequest(explanation=e.format_message())
        except exception.OverQuota as e:
            raise exc.HTTPForbidden(explanation=e.format_message())
        except exception.InstanceIsLocked as e:
            raise exc.HTTPConflict(explanation=e.format_message())
        except exception.InstanceInvalidState as e:
            common.raise_http_conflict_for_instance_invalid_state(
                e, 'live-resize', id)
        except exception.ComputeHostNotFound as e:
            raise exc.HTTPConflict(explanation=e.format_message())
