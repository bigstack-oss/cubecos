# -*- encoding: utf-8 -*-
# Copyright (c) 2015 Intel Corp
#
# Authors: Junjie-Huang <junjie.huang@intel.com>
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

"""
*Good Thermal Strategy*

Towards to software defined infrastructure, the power and thermal
intelligences is being adopted to optimize workload, which can help
improve efficiency, reduce power, as well as to improve datacenter PUE
and lower down operation cost in data center.
Outlet (Exhaust Air) Temperature is one of the important thermal
telemetries to measure thermal/workload status of server.

This strategy makes decisions to migrate workloads to the hosts with good
thermal condition (lowest outlet temperature) when the outlet temperature
of source hosts reach a configurable threshold.
"""

from oslo_log import log

from watcher._i18n import _
from watcher.common import exception
from watcher.decision_engine.model import element
from watcher.decision_engine.strategy.strategies import base


LOG = log.getLogger(__name__)


class OutletTempControl(base.ThermalOptimizationBaseStrategy):
    """[PoC] Outlet temperature control using live migration

    *Description*

    It is a migration strategy based on the outlet temperature of compute
    hosts. It generates solutions to move a workload whenever a server's
    outlet temperature is higher than the specified threshold.

    *Requirements*

    * Hardware: All computer hosts should support IPMI and PTAS technology
    * Software: Ceilometer component ceilometer-agent-ipmi running
      in each compute host, and Ceilometer API can report such telemetry
      ``hardware.ipmi.node.outlet_temperature`` successfully.
    * You must have at least 2 physical compute hosts to run this strategy.

    *Limitations*

    - This is a proof of concept that is not meant to be used in production
    - We cannot forecast how many servers should be migrated. This is the
      reason why we only plan a single virtual machine migration at a time.
      So it's better to use this algorithm with `CONTINUOUS` audits.
    - It assume that live migrations are possible

    *Spec URL*

    https://github.com/openstack/watcher-specs/blob/master/specs/mitaka/implemented/outlet-temperature-based-strategy.rst
    """

    # The meter to report outlet temperature in ceilometer
    MIGRATION = "migrate"

    DATASOURCE_METRICS = ['host_outlet_temp']

    def __init__(self, config, osc=None):
        """Outlet temperature control using live migration

        :param config: A mapping containing the configuration of this strategy
        :type config: dict
        :param osc: an OpenStackClients object, defaults to None
        :type osc: :py:class:`~.OpenStackClients` instance, optional
        """
        super(OutletTempControl, self).__init__(config, osc)

    @classmethod
    def get_name(cls):
        return "outlet_temperature"

    @classmethod
    def get_display_name(cls):
        return _("Outlet temperature based strategy")

    @classmethod
    def get_translatable_display_name(cls):
        return "Outlet temperature based strategy"

    @property
    def period(self):
        return self.input_parameters.get('period', 30)

    @classmethod
    def get_schema(cls):
        # Mandatory default setting for each element
        return {
            "properties": {
                "threshold": {
                    "description": "temperature threshold for migration",
                    "type": "number",
                    "default": 35.0
                },
                "period": {
                    "description": "The time interval in seconds for "
                                   "getting statistic aggregation",
                    "type": "number",
                    "default": 30
                },
                "granularity": {
                    "description": "The time between two measures in an "
                                   "aggregated timeseries of a metric.",
                    "type": "number",
                    "default": 300
                },
            },
        }

    @property
    def granularity(self):
        return self.input_parameters.get('granularity', 300)

    def get_available_compute_nodes(self):
        default_node_scope = [element.ServiceState.ENABLED.value]
        return {uuid: cn for uuid, cn in
                self.compute_model.get_all_compute_nodes().items()
                if cn.state == element.ServiceState.ONLINE.value and
                cn.status in default_node_scope}

    def group_hosts_by_outlet_temp(self):
        """Group hosts based on outlet temp meters"""
        nodes = self.get_available_compute_nodes()
        hosts_need_release = []
        hosts_target = []
        metric_name = 'host_outlet_temp'
        for node in nodes.values():
            outlet_temp = None

            outlet_temp = self.datasource_backend.statistic_aggregation(
                resource=node,
                resource_type='compute_node',
                meter_name=metric_name,
                period=self.period,
                granularity=self.granularity,
            )

            # some hosts may not have outlet temp meters, remove from target
            if outlet_temp is None:
                LOG.warning("%s: no outlet temp data", node.uuid)
                continue

            LOG.debug("%(resource)s: outlet temperature %(temp)f",
                      {'resource': node.uuid, 'temp': outlet_temp})
            instance_data = {'compute_node': node, 'outlet_temp': outlet_temp}
            if outlet_temp >= self.threshold:
                # mark the node to release resources
                hosts_need_release.append(instance_data)
            else:
                hosts_target.append(instance_data)
        return hosts_need_release, hosts_target

    def choose_instance_to_migrate(self, hosts):
        """Pick up an active instance to migrate from provided hosts"""
        for instance_data in hosts:
            mig_source_node = instance_data['compute_node']
            instances_of_src = self.compute_model.get_node_instances(
                mig_source_node)
            for instance in instances_of_src:
                try:
                    # NOTE: skip exclude instance when migrating
                    if instance.watcher_exclude:
                        LOG.debug("Instance is excluded by scope, "
                                  "skipped: %s", instance.uuid)
                        continue
                    # select the first active instance to migrate
                    if (instance.state !=
                            element.InstanceState.ACTIVE.value):
                        LOG.info("Instance not active, skipped: %s",
                                 instance.uuid)
                        continue
                    return mig_source_node, instance
                except exception.InstanceNotFound as e:
                    LOG.exception(e)
                    LOG.info("Instance not found")

        return None

    def filter_dest_servers(self, hosts, instance_to_migrate):
        """Only return hosts with sufficient available resources"""
        required_cores = instance_to_migrate.vcpus
        required_disk = instance_to_migrate.disk
        required_memory = instance_to_migrate.memory

        # filter nodes without enough resource
        dest_servers = []
        for instance_data in hosts:
            host = instance_data['compute_node']
            # available
            free_res = self.compute_model.get_node_free_resources(host)
            if (free_res['vcpu'] >= required_cores and free_res['disk'] >=
                    required_disk and free_res['memory'] >= required_memory):
                dest_servers.append(instance_data)

        return dest_servers

    def pre_execute(self):
        self._pre_execute()
        # the migration plan will be triggered when the outlet temperature
        # reaches threshold
        self.threshold = self.input_parameters.threshold
        LOG.info("Outlet temperature strategy threshold=%d",
                 self.threshold)

    def do_execute(self, audit=None):
        hosts_need_release, hosts_target = self.group_hosts_by_outlet_temp()

        if len(hosts_need_release) == 0:
            # TODO(zhenzanz): return something right if there's no hot servers
            LOG.debug("No hosts require optimization")
            return self.solution

        if len(hosts_target) == 0:
            LOG.warning("No hosts under outlet temp threshold found")
            return self.solution

        # choose the server with highest outlet t
        hosts_need_release = sorted(hosts_need_release,
                                    reverse=True,
                                    key=lambda x: (x["outlet_temp"]))

        instance_to_migrate = self.choose_instance_to_migrate(
            hosts_need_release)
        # calculate the instance's cpu cores,memory,disk needs
        if instance_to_migrate is None:
            return self.solution

        mig_source_node, instance_src = instance_to_migrate
        dest_servers = self.filter_dest_servers(hosts_target, instance_src)
        # sort the filtered result by outlet temp
        # pick up the lowest one as dest server
        if len(dest_servers) == 0:
            # TODO(zhenzanz): maybe to warn that there's no resource
            # for instance.
            LOG.info("No proper target host could be found")
            return self.solution

        dest_servers = sorted(dest_servers, key=lambda x: (x["outlet_temp"]))
        # always use the host with lowerest outlet temperature
        mig_destination_node = dest_servers[0]['compute_node']
        # generate solution to migrate the instance to the dest server,
        if self.compute_model.migrate_instance(
                instance_src, mig_source_node, mig_destination_node):
            parameters = {'migration_type': 'live',
                          'source_node': mig_source_node.uuid,
                          'destination_node': mig_destination_node.uuid,
                          'resource_name': instance_src.name}
            self.solution.add_action(action_type=self.MIGRATION,
                                     resource_id=instance_src.uuid,
                                     input_parameters=parameters)

    def post_execute(self):
        self.solution.model = self.compute_model
        # TODO(v-francoise): Add the indicators to the solution

        LOG.debug(self.compute_model.to_string())
