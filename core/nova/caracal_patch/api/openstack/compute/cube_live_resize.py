# Cube downstream: live-resize server action (vCPU/memory hot-add).

from webob import exc

from nova.api.openstack import common
from nova.api.openstack import wsgi
from nova.api import validation
from nova.compute import api as compute
from nova import exception
from nova.policies import live_resize as lr_policies
from nova.policies import servers as server_policies

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


cube_resize_schema = {
    'type': 'object',
    'properties': {
        'cube-resize': {
            'type': 'object',
            'properties': {
                'flavorRef': {'type': ['string', 'integer'],
                              'minLength': 1},
                # The caller states the mode it was shown and consented to.
                # There is deliberately no 'auto': falling back from live to
                # cold on the operator's behalf would reboot the guest, move
                # it to another host and strand it in VERIFY_RESIZE holding
                # allocations on two hosts. Cold is downtime, and downtime is
                # consented to, never inferred.
                'mode': {'type': 'string', 'enum': ['live', 'cold']},
            },
            'required': ['flavorRef', 'mode'],
            'additionalProperties': False,
        },
    },
    'required': ['cube-resize'],
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

    @wsgi.response(202)
    @wsgi.expected_errors((400, 403, 404, 409))
    @wsgi.action('cube-resize')
    @validation.schema(cube_resize_schema)
    def _cube_resize(self, req, id, body):
        """One resize action; the caller states the mode it consented to.

        The mode is re-checked here rather than trusted: the caller decided
        from a resize-plan envelope fetched when its dialog opened, and the
        instance may have moved on since. A 'live' request that is no longer
        possible fails with the reason -- it is never quietly served cold.
        """
        context = req.environ['nova.context']
        instance = common.get_instance(self.compute_api, context, id)
        args = body['cube-resize']
        flavor_ref = str(args['flavorRef'])

        if args['mode'] == 'live':
            context.can(lr_policies.BASE_POLICY_NAME,
                        target={'project_id': instance.project_id})
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
                    e, 'cube-resize', id)
            except exception.ComputeHostNotFound as e:
                raise exc.HTTPConflict(explanation=e.format_message())
            return

        # cold: the upstream resize policy governs, so a deployment can grant
        # live-resize without also granting the right to reboot someone's guest
        context.can(server_policies.SERVERS % 'resize',
                    target={'user_id': instance.user_id,
                            'project_id': instance.project_id})
        try:
            self.compute_api.resize(context, instance, flavor_ref)
        except exception.OverQuota as e:
            raise exc.HTTPForbidden(explanation=e.format_message())
        except (exception.InstanceIsLocked,
                exception.InstanceNotReady,
                exception.ServiceUnavailable) as e:
            raise exc.HTTPConflict(explanation=e.format_message())
        except exception.InstanceInvalidState as e:
            common.raise_http_conflict_for_instance_invalid_state(
                e, 'cube-resize', id)
        except (exception.CannotResizeDisk,
                exception.CannotResizeToSameFlavor,
                exception.FlavorNotFound) as e:
            raise exc.HTTPBadRequest(explanation=e.format_message())
