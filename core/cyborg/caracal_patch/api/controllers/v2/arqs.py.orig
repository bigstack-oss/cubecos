# Copyright 2019 Intel, Inc.
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

from http import HTTPStatus
import pecan
import wsme
from wsme import types as wtypes

from oslo_log import log

from cyborg.api.controllers import base
from cyborg.api.controllers import link
from cyborg.api.controllers import types
from cyborg.api.controllers.v2 import utils
from cyborg.api.controllers.v2 import versions
from cyborg.api import expose
from cyborg.common import authorize_wsgi
from cyborg.common import constants
from cyborg.common import exception
from cyborg.common.i18n import _
from cyborg import objects

LOG = log.getLogger(__name__)


class ARQ(base.APIBase):
    """API representation of an ARQ.

    This class enforces type checking and value constraints, and converts
    between the internal object model and the API representation.
    """
    uuid = types.uuid
    """The UUID of the ARQ"""

    state = wtypes.text  # obvious meanings
    device_profile_name = wtypes.text
    device_profile_group_id = wtypes.IntegerType()

    hostname = wtypes.text
    """The host name to which the ARQ is bound, if any"""

    device_rp_uuid = types.uuid
    """The UUID of the bound device RP, if any"""

    instance_uuid = types.uuid
    """The UUID of the instance associated with this ARQ, if any"""
    project_id = types.uuid
    """The UUID of the instance project_id associated with this ARQ, if any"""

    attach_handle_type = wtypes.text
    attach_handle_uuid = wtypes.text
    attach_handle_info = {wtypes.text: wtypes.text}

    links = wsme.wsattr([link.Link], readonly=True)
    """A list containing a self link"""

    def __init__(self, **kwargs):
        super(ARQ, self).__init__(**kwargs)
        self.fields = []
        for field in objects.ARQ.fields:
            self.fields.append(field)
            setattr(self, field, kwargs.get(field, wtypes.Unset))

    @classmethod
    def convert_with_links(cls, obj_arq):
        api_arq = cls(**obj_arq.as_dict())
        api_arq.links = [
            link.Link.make_link('self', pecan.request.public_url,
                                'accelerator_requests', api_arq.uuid)
            ]
        return api_arq


class ARQCollection(base.APIBase):
    """API representation of a collection of arqs."""

    arqs = [ARQ]
    """A list containing arq objects"""

    @classmethod
    def convert_with_links(cls, obj_arqs):
        collection = cls()
        collection.arqs = [ARQ.convert_with_links(obj_arq)
                           for obj_arq in obj_arqs]
        return collection


class ARQsController(base.CyborgController):
    """REST controller for ARQs.

       For the relationship between ARQs and device profiles, see
       nova/nova/accelerator/cyborg.py.
    """

    @authorize_wsgi.authorize_wsgi("cyborg:arq", "create", False)
    @expose.expose(ARQCollection, body=types.jsontype,
                   status_code=HTTPStatus.CREATED)
    def post(self, req):
        """Create one or more ARQs for a single device profile.
           Request body:
              { 'device_profile_name': <string> }
           Future:
              { 'device_profile_name': <string> # required
                'device_profile_group_id': <integer>, # opt, default=0
                'image_uuid': <glance-image-UUID>, #optional, for future
              }
           :param req: request body.
        """
        LOG.info("[arq] post req = (%s)", req)
        context = pecan.request.context
        dp_name = req.get('device_profile_name')
        if dp_name is not None:
            try:
                devprof = objects.DeviceProfile.get_by_name(context, dp_name)
            except exception.ResourceNotFound:
                raise exception.ResourceNotFound(
                    resource='Device Profile',
                    msg='with name=%s' % dp_name)
            except Exception as e:
                raise e
        else:
            raise exception.DeviceProfileNameNeeded()
        LOG.info('[arqs] post. device profile name=%s', dp_name)

        extarq_list = []
        for group_id, group in enumerate(devprof.groups):
            accel_resources = []
            # If the device profile requires the Xilinx fpga, the number of
            # resources should multiply by 2 cause that end user can program
            # the device only when both MGMT and USER PF are bound to
            # instance.
            if group.get("trait:CUSTOM_FPGA_XILINX") == "required":
                accel_resources = [int(group.get("resources:FPGA"))] * 2
            else:
                accel_resources = [
                    int(val) for key, val in group.items()
                    if key.startswith('resources')]

            # If/when we introduce non-accelerator resources, like
            # device-local memory, the key search above needs to be
            # made specific to accelerator resources only.
            num_accels = sum(accel_resources)
            arq_fields = {
                'device_profile_name': devprof.name,
                'device_profile_group_id': group_id,
            }
            for i in range(num_accels):
                obj_arq = objects.ARQ(context, **arq_fields)
                extarq_fields = {'arq': obj_arq}
                obj_extarq = objects.ExtARQ(context, **extarq_fields)
                new_extarq = pecan.request.conductor_api.arq_create(
                    context, obj_extarq, devprof.id)
                extarq_list.append(new_extarq)

        ret = ARQCollection.convert_with_links(
            [extarq.arq for extarq in extarq_list])
        LOG.info('[arqs] post returned: %s', ret)
        return ret

    @authorize_wsgi.authorize_wsgi("cyborg:arq", "get_one")
    @expose.expose(ARQ, types.uuid)
    def get_one(self, uuid):
        """Get a single ARQ by UUID."""
        context = pecan.request.context
        extarq = objects.ExtARQ.get(context, uuid)
        return ARQ.convert_with_links(extarq.arq)

    @authorize_wsgi.authorize_wsgi("cyborg:arq", "get_all", False)
    @expose.expose(ARQCollection, wtypes.text, types.uuid)
    def get_all(self, bind_state=None, instance=None):
        """Retrieve a list of arqs."""
        # TODO(Sundar) Need to implement 'arq=uuid1,...' query parameter
        LOG.info('[arqs] get_all. bind_state:(%s), instance:(%s)',
                 bind_state or '', instance or '')
        context = pecan.request.context
        extarqs = objects.ExtARQ.list(context)
        state_map = constants.ARQ_BIND_STATES_STATUS_MAP
        valid_bind_states = list(state_map.keys())
        arqs = [extarq.arq for extarq in extarqs]
        # TODO(Sundar): Optimize by doing the filtering in the db layer
        # Apply instance filter before state filter.
        if bind_state and bind_state != 'resolved':
            raise exception.ARQBadState(
                state=bind_state, uuid=None, expected=['resolved'])
        if instance:
            new_arqs = [arq for arq in arqs
                        if arq['instance_uuid'] == instance]
            arqs = new_arqs
            if bind_state:
                for arq in new_arqs:
                    if arq['state'] not in valid_bind_states:
                        # NOTE(Sundar) This should return HTTP code 423
                        # if any ARQ for this instance is not resolved.
                        LOG.warning('Some of ARQs for instance %s is not '
                                    'resolved', instance)
                        return wsme.api.Response(
                            None,
                            status_code=HTTPStatus.LOCKED)
        elif bind_state:
            arqs = [arq for arq in arqs
                    if arq['state'] in valid_bind_states]

        ret = ARQCollection.convert_with_links(arqs)
        LOG.info('[arqs:get_all] Returned: %s', ret)
        return ret

    @authorize_wsgi.authorize_wsgi("cyborg:arq", "delete", False)
    @expose.expose(None, wtypes.text, types.uuid,
                   status_code=HTTPStatus.NO_CONTENT)
    def delete(self, arqs=None, instance=None):
        """Delete one or more ARQS.

        The request can be either one of these two forms:
            DELETE /v2/accelerator_requests?arqs=uuid1,uuid2,...
            DELETE /v2/accelerator_requests?instance=uuid

        The second form is idempotent, i.e., it would have the same effect
        if called repeatedly with the same instance UUID. In other words,
        it would not raise an error on the second and later attempts even if
        the first one has deleted the ARQs. Whereas the first form is not
        idempotent: if one or more of the ARQs do not exist, it would raise
        an error. Nova uses the second form: so repeated calls do not cause
        issues.

        :param arqs: List of ARQ UUIDs
        :param instance: UUID of instance whose ARQs need to be deleted
        """
        context = pecan.request.context
        if (arqs and instance) or (not arqs and not instance):
            raise exception.ObjectActionError(
                action='delete',
                reason='Provide either an ARQ uuid list or an instance UUID')
        elif arqs:
            LOG.info("[arqs] delete. arqs=(%s)", arqs)
            pecan.request.conductor_api.arq_delete_by_uuid(context, arqs)
        else:  # instance is not None
            LOG.info("[arqs] delete. instance=(%s)", instance)
            pecan.request.conductor_api.arq_delete_by_instance_uuid(
                context, instance)

    def _validate_arq_patch(self, patch):
        """Validate a single patch for an ARQ.

        :param patch: a JSON PATCH document.
            The patch must be of the form [{..}], as specified in the
            value field of arq_uuid in patch() method below.
        :returns: dict of valid fields
        """
        valid_fields = {'hostname': None,
                        'device_rp_uuid': None,
                        'instance_uuid': None}
        if utils.allow_project_id():
            valid_fields['project_id'] = None
        if ((not all(p['op'] == 'add' for p in patch)) and
           (not all(p['op'] == 'remove' for p in patch))):
            raise exception.PatchError(
                reason='Every op must be add or remove')

        for p in patch:
            path = p['path'].lstrip('/')
            if path == 'project_id' and not utils.allow_project_id():
                raise exception.NotAcceptable(_(
                    "Request not acceptable. The minimal required API "
                    "version should be %(base)s.%(opr)s") %
                    {'base': versions.BASE_VERSION,
                     'opr': versions.MINOR_1_PROJECT_ID})
            if path not in valid_fields.keys():
                reason = 'Invalid path in patch {}'.format(p['path'])
                raise exception.PatchError(reason=reason)
            if p['op'] == 'add':
                valid_fields[path] = p['value']
        not_found = [field for field, value in valid_fields.items()
                     if value is None]
        if patch[0]['op'] == 'add' and len(not_found) > 0:
            msg = ','.join(not_found)
            reason = _('Fields absent in patch {}').format(msg)
            raise exception.PatchError(reason=reason)

        return valid_fields

    @staticmethod
    def _check_if_already_bound(context, valid_fields):
        patch_fields = list(valid_fields.values())[0]
        instance_uuid = patch_fields['instance_uuid']
        extarqs = objects.ExtARQ.list(context)
        extarqs_for_instance = [
            extarq for extarq in extarqs
            if extarq.arq['instance_uuid'] == instance_uuid]
        if extarqs_for_instance:  # duplicate binding request
            msg = _('Instance {} already has accelerator requests. '
                    'Cannot bind additional ARQs.')
            reason = msg.format(instance_uuid)
            raise exception.PatchError(reason=reason)

    @authorize_wsgi.authorize_wsgi("cyborg:arq", "update", False)
    @expose.expose(None, body=types.jsontype,
                   status_code=HTTPStatus.ACCEPTED)
    def patch(self, patch_list):
        """Bind/Unbind one or more ARQs.

        Usage: curl -X PATCH .../v2/accelerator_requests
                 -d <patch_list> -H "Content-type: application/json"

        :param patch_list: A map from ARQ UUIDs to their JSON patches:
            {"$arq_uuid": [
                {"path": "/hostname", "op": ADD/RM, "value": "..."},
                {"path": "/device_rp_uuid", "op": ADD/RM, "value": "..."},
                {"path": "/instance_uuid", "op": ADD/RM, "value": "..."},
                {"path": "/project_id", "op": ADD/RM, "value": "..."},
               ],
             "$arq_uuid": [...]
            }
            In particular, all and only these 4 fields must be present,
            and only 'add' or 'remove' ops are allowed.
        """
        LOG.info('[arqs] patch. list=(%s)', patch_list)
        context = pecan.request.context
        # Validate all patches before un/binding.
        valid_fields = {}
        for arq_uuid, patch in patch_list.items():
            valid_fields[arq_uuid] = self._validate_arq_patch(patch)

        # NOTE(Sundar): In the ARQ create/bind flow, new ARQs can be created
        # for a device profile any time. However, they should not be bound to
        # an instance which already has other ARQs bound to it. In the future,
        # we may allow that for hot adds, but not now.
        # See commit message of https://review.opendev.org/712231 for details.
        #
        # So, for bind requests, we first check that no ARQs are already
        # associated with the instance specified in the binding.
        patch = list(patch_list.values())[0]
        if patch[0]['op'] == 'add':
            self._check_if_already_bound(context, valid_fields)

        pecan.request.conductor_api.arq_apply_patch(
            context, patch_list, valid_fields)
