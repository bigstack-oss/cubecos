# -*- encoding: utf-8 -*-
# Copyright (c) 2017 Intel Corp
#
# Authors: Prudhvi Rao Shedimbi <prudhvi.rao.shedimbi@intel.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
from oslo_config import cfg
from oslo_log import log

from watcher._i18n import _
from watcher.decision_engine.strategy.strategies import base

LOG = log.getLogger(__name__)
CONF = cfg.CONF


class NoisyNeighbor(base.NoisyNeighborBaseStrategy):
    """Noisy Neighbor strategy using live migration

    *Description*

    This strategy can identify and migrate a Noisy Neighbor -
    a low priority VM that negatively affects performance of
    a high priority VM in terms of IPC by over utilizing
    Last Level Cache.

    *Requirements*

    To enable LLC metric, latest Intel server with CMT support is required.

    *Limitations*

    This is a proof of concept that is not meant to be used in production

    *Spec URL*

    http://specs.openstack.org/openstack/watcher-specs/specs/pike/implemented/noisy_neighbor_strategy.html
    """

    MIGRATION = "migrate"

    DATASOURCE_METRICS = ['instance_l3_cache_usage']

    DEFAULT_WATCHER_PRIORITY = 5

    def __init__(self, config, osc=None):
        super(NoisyNeighbor, self).__init__(config, osc)

        self.meter_name = 'instance_l3_cache_usage'

    @classmethod
    def get_name(cls):
        return "noisy_neighbor"

    @classmethod
    def get_display_name(cls):
        return _("Noisy Neighbor")

    @classmethod
    def get_translatable_display_name(cls):
        return "Noisy Neighbor"

    @classmethod
    def get_schema(cls):
        # Mandatory default setting for each element
        return {
            "properties": {
                "cache_threshold": {
                    "description": "Performance drop in L3_cache threshold "
                                   "for migration",
                    "type": "number",
                    "default": 35.0
                },
                "period": {
                    "description": "Aggregate time period of "
                                   "ceilometer and gnocchi",
                    "type": "number",
                    "default": 100.0
                },
            },
        }

    def get_current_and_previous_cache(self, instance):
        try:
            curr_cache = self.datasource_backend.get_instance_l3_cache_usage(
                instance, self.meter_name, self.period,
                'mean', granularity=300)
            previous_cache = 2 * (
                self.datasource_backend.get_instance_l3_cache_usage(
                    instance, self.meter_name, 2 * self.period,
                    'mean', granularity=300)) - curr_cache

        except Exception as exc:
            LOG.exception(exc)
            return None, None

        return curr_cache, previous_cache

    def find_priority_instance(self, instance):

        current_cache, previous_cache = \
            self.get_current_and_previous_cache(instance)

        if None in (current_cache, previous_cache):
            LOG.warning("Datasource unable to pick L3 Cache "
                        "values. Skipping the instance")
            return None

        if (current_cache < (1 - (self.cache_threshold / 100.0)) *
                previous_cache):
            return instance
        else:
            return None

    def find_noisy_instance(self, instance):

        noisy_current_cache, noisy_previous_cache = \
            self.get_current_and_previous_cache(instance)

        if None in (noisy_current_cache, noisy_previous_cache):
            LOG.warning("Datasource unable to pick "
                        "L3 Cache. Skipping the instance")
            return None

        if (noisy_current_cache > (1 + (self.cache_threshold / 100.0)) *
                noisy_previous_cache):
            return instance
        else:
            return None

    def group_hosts(self):
        nodes = self.compute_model.get_all_compute_nodes()
        hosts_need_release = {}
        hosts_target = []

        for node in nodes.values():
            instances_of_node = self.compute_model.get_node_instances(node)
            node_instance_count = len(instances_of_node)

            # Flag that tells us whether to skip the node or not. If True,
            # the node is skipped. Will be true if we find a noisy instance or
            # when potential priority instance will be same as potential noisy
            # instance
            loop_break_flag = False

            if node_instance_count > 1:

                instance_priority_list = []

                for instance in instances_of_node:
                    instance_priority_list.append(instance)

                # If there is no metadata regarding watcher-priority, it takes
                # DEFAULT_WATCHER_PRIORITY as priority.
                instance_priority_list.sort(key=lambda a: (
                    a.get('metadata').get('watcher-priority'),
                    self.DEFAULT_WATCHER_PRIORITY))

                instance_priority_list_reverse = list(instance_priority_list)
                instance_priority_list_reverse.reverse()

                for potential_priority_instance in instance_priority_list:

                    priority_instance = self.find_priority_instance(
                        potential_priority_instance)

                    if (priority_instance is not None):

                        for potential_noisy_instance in (
                                instance_priority_list_reverse):
                            if (potential_noisy_instance ==
                                    potential_priority_instance):
                                loop_break_flag = True
                                break

                            noisy_instance = self.find_noisy_instance(
                                potential_noisy_instance)

                            if noisy_instance is not None:
                                hosts_need_release[node.uuid] = {
                                    'priority_vm': potential_priority_instance,
                                    'noisy_vm': potential_noisy_instance}
                                LOG.debug("Priority VM found: %s",
                                          potential_priority_instance.uuid)
                                LOG.debug("Noisy VM found: %s",
                                          potential_noisy_instance.uuid)
                                loop_break_flag = True
                                break

                    # No need to check other instances in the node
                    if loop_break_flag is True:
                        break

            if node.uuid not in hosts_need_release:
                hosts_target.append(node)

        return hosts_need_release, hosts_target

    def filter_dest_servers(self, hosts, instance_to_migrate):
        required_cores = instance_to_migrate.vcpus
        required_disk = instance_to_migrate.disk
        required_memory = instance_to_migrate.memory

        dest_servers = []
        for host in hosts:
            free_res = self.compute_model.get_node_free_resources(host)
            if (free_res['vcpu'] >= required_cores and free_res['disk'] >=
                    required_disk and free_res['memory'] >= required_memory):
                dest_servers.append(host)

        return dest_servers

    def pre_execute(self):
        self._pre_execute()

    def do_execute(self, audit=None):
        self.cache_threshold = self.input_parameters.cache_threshold
        self.period = self.input_parameters.period

        hosts_need_release, hosts_target = self.group_hosts()

        if len(hosts_need_release) == 0:
            LOG.debug("No hosts require optimization")
            return

        if len(hosts_target) == 0:
            LOG.debug("No hosts available to migrate")
            return

        mig_source_node_name = max(hosts_need_release.keys(), key=lambda a:
                                   hosts_need_release[a]['priority_vm'])
        instance_to_migrate = hosts_need_release[mig_source_node_name][
            'noisy_vm']

        if instance_to_migrate is None:
            return

        dest_servers = self.filter_dest_servers(hosts_target,
                                                instance_to_migrate)

        if len(dest_servers) == 0:
            LOG.info("No proper target host could be found")
            return

        # Destination node will be the first available node in the list.
        mig_destination_node = dest_servers[0]
        mig_source_node = self.compute_model.get_node_by_uuid(
            mig_source_node_name)

        if self.compute_model.migrate_instance(instance_to_migrate,
                                               mig_source_node,
                                               mig_destination_node):
            parameters = {'migration_type': 'live',
                          'source_node': mig_source_node.uuid,
                          'destination_node': mig_destination_node.uuid,
                          'resource_name': instance_to_migrate.name}
            self.solution.add_action(action_type=self.MIGRATION,
                                     resource_id=instance_to_migrate.uuid,
                                     input_parameters=parameters)

    def post_execute(self):
        self.solution.model = self.compute_model

        LOG.debug(self.compute_model.to_string())
