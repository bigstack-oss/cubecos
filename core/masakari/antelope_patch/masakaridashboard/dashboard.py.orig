# Copyright (C) 2018 NTT DATA
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

from oslo_log import log as logging

from django.utils.translation import ugettext_lazy as _

import horizon

from masakaridashboard.api import api
from masakaridashboard.default import panel

LOG = logging.getLogger(__name__)


class MasakariDashboard(horizon.Dashboard):
    slug = "masakaridashboard"
    name = _("Instance-ha")
    panels = ('default', 'segments', 'hosts', 'notifications')
    default_panel = 'default'
    policy_rules = (('instance-ha', 'context_is_admin'),)

    def allowed(self, context):
        # disable whole dashboard if masakari
        # is not present in the service catalog
        try:
            # NOTE(pas-ha) this method tries to construct keystoneauth.Adapter
            # for the Instance-HA service,
            # which will fail if the service is absent
            api.openstack_connection(context['request'])
        except Exception as e:
            # catch all errors and log them,
            # no need to totally fail on e.g. HTTP connect failure
            LOG.warning(f"Failed to find suitable endpoint for Instance HA "
                        f"service, Masakari Dashboard will not be displayed. "
                        f"Error was: {e}")
            return False
        return super().allowed(context)


horizon.register(MasakariDashboard)
MasakariDashboard.register(panel.Default)
