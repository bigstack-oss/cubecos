# Copyright (c) 2011-2012 OpenStack Foundation
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

import nova.conf
from nova.scheduler import filters

LOG = logging.getLogger(__name__)

CONF = nova.conf.CONF


# Cube downstream: Nova 29 removed AvailabilityZoneFilter. Its replacement,
# map_az_to_placement_aggregate, restricts requests only for AZs on aggregates.
# No aggregate carries CONF.default_availability_zone ("nova"), so default-AZ
# requests otherwise remain unrestricted and can land on named-AZ hosts.
class CubeAvailabilityZoneFilter(filters.BaseHostFilter):
    """Filters Hosts by availability zone.

    Works with aggregate metadata availability zones, using the key
    'availability_zone'
    Note: in theory a compute node can be part of multiple availability_zones
    """

    # Availability zones do not change within a request
    run_filter_once_per_request = True

    RUN_ON_REBUILD = False

    def host_passes(self, host_state, spec_obj):
        availability_zone = spec_obj.availability_zone

        if not availability_zone:
            return True

        # Whole values, not utils.aggregate_metadata_get_by_host: nova accepts
        # ',' in an AZ name, and that helper splits on it.
        host_azs = {aggr.metadata['availability_zone']
                    for aggr in host_state.aggregates
                    if 'availability_zone' in aggr.metadata}

        if host_azs:
            hosts_passes = availability_zone in host_azs
            host_az = host_azs
        else:
            hosts_passes = availability_zone == CONF.default_availability_zone
            host_az = CONF.default_availability_zone

        if not hosts_passes:
            LOG.debug("Availability Zone '%(az)s' requested. "
                      "%(host_state)s has AZs: %(host_az)s",
                      {'host_state': host_state,
                       'az': availability_zone,
                       'host_az': host_az})

        return hosts_passes
