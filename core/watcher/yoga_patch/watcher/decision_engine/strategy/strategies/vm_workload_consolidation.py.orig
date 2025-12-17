# -*- encoding: utf-8 -*-
#
# Authors: Vojtech CIMA <cima@zhaw.ch>
#          Bruno GRAZIOLI <gaea@zhaw.ch>
#          Sean MURPHY <murp@zhaw.ch>
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

from oslo_log import log

from watcher._i18n import _
from watcher.common import exception
from watcher.decision_engine.model import element
from watcher.decision_engine.strategy.strategies import base

LOG = log.getLogger(__name__)


class VMWorkloadConsolidation(base.ServerConsolidationBaseStrategy):
    """VM Workload Consolidation Strategy

    A load consolidation strategy based on heuristic first-fit
    algorithm which focuses on measured CPU utilization and tries to
    minimize hosts which have too much or too little load respecting
    resource capacity constraints.

    This strategy produces a solution resulting in more efficient
    utilization of cluster resources using following four phases:

    * Offload phase - handling over-utilized resources
    * Consolidation phase - handling under-utilized resources
    * Solution optimization - reducing number of migrations
    * Disability of unused compute nodes

    A capacity coefficients (cc) might be used to adjust optimization
    thresholds. Different resources may require different coefficient
    values as well as setting up different coefficient values in both
    phases may lead to more efficient consolidation in the end.
    If the cc equals 1 the full resource capacity may be used, cc
    values lower than 1 will lead to resource under utilization and
    values higher than 1 will lead to resource overbooking.
    e.g. If targeted utilization is 80 percent of a compute node capacity,
    the coefficient in the consolidation phase will be 0.8, but
    may any lower value in the offloading phase. The lower it gets
    the cluster will appear more released (distributed) for the
    following consolidation phase.

    As this strategy leverages VM live migration to move the load
    from one compute node to another, this feature needs to be set up
    correctly on all compute nodes within the cluster.
    This strategy assumes it is possible to live migrate any VM from
    an active compute node to any other active compute node.
    """

    AGGREGATE = 'mean'
    DATASOURCE_METRICS = ['instance_ram_allocated', 'instance_cpu_usage',
                          'instance_ram_usage', 'instance_root_disk_size']

    MIGRATION = "migrate"
    CHANGE_NOVA_SERVICE_STATE = "change_nova_service_state"

    def __init__(self, config, osc=None):
        super(VMWorkloadConsolidation, self).__init__(config, osc)
        self.number_of_migrations = 0
        self.number_of_released_nodes = 0
        self.datasource_instance_data_cache = dict()

    @classmethod
    def get_name(cls):
        return "vm_workload_consolidation"

    @classmethod
    def get_display_name(cls):
        return _("VM Workload Consolidation Strategy")

    @classmethod
    def get_translatable_display_name(cls):
        return "VM Workload Consolidation Strategy"

    @property
    def period(self):
        return self.input_parameters.get('period', 3600)

    @property
    def granularity(self):
        return self.input_parameters.get('granularity', 300)

    @classmethod
    def get_schema(cls):
        # Mandatory default setting for each element
        return {
            "properties": {
                "period": {
                    "description": "The time interval in seconds for "
                                   "getting statistic aggregation",
                    "type": "number",
                    "default": 3600
                },
                "granularity": {
                    "description": "The time between two measures in an "
                                   "aggregated timeseries of a metric.",
                    "type": "number",
                    "default": 300
                },
            }
        }

    def get_available_compute_nodes(self):
        default_node_scope = [element.ServiceState.ENABLED.value,
                              element.ServiceState.DISABLED.value]
        nodes = self.compute_model.get_all_compute_nodes().items()
        return {uuid: cn for uuid, cn in
                nodes
                if cn.state == element.ServiceState.ONLINE.value and
                cn.status in default_node_scope}

    def get_instance_state_str(self, instance):
        """Get instance state in string format.

        :param instance:
        """
        if isinstance(instance.state, str):
            return instance.state
        elif isinstance(instance.state, element.InstanceState):
            return instance.state.value
        else:
            LOG.error('Unexpected instance state type, '
                      'state=%(state)s, state_type=%(st)s.',
                      dict(state=instance.state,
                           st=type(instance.state)))
            raise exception.WatcherException

    def get_node_status_str(self, node):
        """Get node status in string format.

        :param node:
        """
        if isinstance(node.status, str):
            return node.status
        elif isinstance(node.status, element.ServiceState):
            return node.status.value
        else:
            LOG.error('Unexpected node status type, '
                      'status=%(status)s, status_type=%(st)s.',
                      dict(status=node.status,
                           st=type(node.status)))
            raise exception.WatcherException

    def add_action_enable_compute_node(self, node):
        """Add an action for node enabler into the solution.

        :param node: node object
        :return: None
        """
        params = {'state': element.ServiceState.ENABLED.value,
                  'resource_name': node.hostname}
        self.solution.add_action(
            action_type=self.CHANGE_NOVA_SERVICE_STATE,
            resource_id=node.uuid,
            input_parameters=params)
        self.number_of_released_nodes -= 1

    def add_action_disable_node(self, node):
        """Add an action for node disability into the solution.

        :param node: node object
        :return: None
        """
        params = {'state': element.ServiceState.DISABLED.value,
                  'disabled_reason': self.REASON_FOR_DISABLE,
                  'resource_name': node.hostname}
        self.solution.add_action(
            action_type=self.CHANGE_NOVA_SERVICE_STATE,
            resource_id=node.uuid,
            input_parameters=params)
        self.number_of_released_nodes += 1

    def add_migration(self, instance, source_node, destination_node):
        """Add an action for VM migration into the solution.

        :param instance: instance object
        :param source_node: node object
        :param destination_node: node object
        :return: None
        """
        instance_state_str = self.get_instance_state_str(instance)
        if instance_state_str not in (element.InstanceState.ACTIVE.value,
                                      element.InstanceState.PAUSED.value):
            # Watcher currently only supports live VM migration and block live
            # VM migration which both requires migrated VM to be active.
            # When supported, the cold migration may be used as a fallback
            # migration mechanism to move non active VMs.
            LOG.error(
                'Cannot live migrate: instance_uuid=%(instance_uuid)s, '
                'state=%(instance_state)s.', dict(
                    instance_uuid=instance.uuid,
                    instance_state=instance_state_str))
            return

        migration_type = 'live'

        # Here will makes repeated actions to enable the same compute node,
        # when migrating VMs to the destination node which is disabled.
        # Whether should we remove the same actions in the solution???
        destination_node_status_str = self.get_node_status_str(
            destination_node)
        if destination_node_status_str == element.ServiceState.DISABLED.value:
            self.add_action_enable_compute_node(destination_node)

        if self.compute_model.migrate_instance(
                instance, source_node, destination_node):
            self.add_action_migrate(
                instance,
                migration_type,
                source_node,
                destination_node)
            self.number_of_migrations += 1

    def disable_unused_nodes(self):
        """Generate actions for disabling unused nodes.

        :return: None
        """
        for node in self.get_available_compute_nodes().values():
            if (len(self.compute_model.get_node_instances(node)) == 0 and
                    node.status !=
                    element.ServiceState.DISABLED.value):
                self.add_action_disable_node(node)

    def get_instance_utilization(self, instance):
        """Collect cpu, ram and disk utilization statistics of a VM.

        :param instance: instance object
        :param aggr: string
        :return: dict(cpu(number of vcpus used), ram(MB used), disk(B used))
        """
        instance_cpu_util = None
        instance_ram_util = None
        instance_disk_util = None

        if instance.uuid in self.datasource_instance_data_cache.keys():
            return self.datasource_instance_data_cache.get(instance.uuid)

        instance_cpu_util = self.datasource_backend.get_instance_cpu_usage(
            resource=instance, period=self.period,
            aggregate=self.AGGREGATE, granularity=self.granularity)
        instance_ram_util = self.datasource_backend.get_instance_ram_usage(
            resource=instance, period=self.period,
            aggregate=self.AGGREGATE, granularity=self.granularity)
        if not instance_ram_util:
            instance_ram_util = (
                self.datasource_backend.get_instance_ram_allocated(
                    resource=instance, period=self.period,
                    aggregate=self.AGGREGATE, granularity=self.granularity))
        instance_disk_util = (
            self.datasource_backend.get_instance_root_disk_size(
                resource=instance, period=self.period,
                aggregate=self.AGGREGATE, granularity=self.granularity))

        if instance_cpu_util:
            total_cpu_utilization = (
                instance.vcpus * (instance_cpu_util / 100.0))
        else:
            total_cpu_utilization = instance.vcpus

        if not instance_ram_util:
            instance_ram_util = instance.memory
            LOG.warning('No values returned by %s for memory.resident, '
                        'use instance flavor ram value', instance.uuid)

        if not instance_disk_util:
            instance_disk_util = instance.disk
            LOG.warning('No values returned by %s for disk.root.size, '
                        'use instance flavor disk value', instance.uuid)

        self.datasource_instance_data_cache[instance.uuid] = dict(
            cpu=total_cpu_utilization, ram=instance_ram_util,
            disk=instance_disk_util)
        return self.datasource_instance_data_cache.get(instance.uuid)

    def get_node_utilization(self, node):
        """Collect cpu, ram and disk utilization statistics of a node.

        :param node: node object
        :param aggr: string
        :return: dict(cpu(number of cores used), ram(MB used), disk(B used))
        """
        node_instances = self.compute_model.get_node_instances(node)
        node_ram_util = 0
        node_disk_util = 0
        node_cpu_util = 0
        for instance in node_instances:
            instance_util = self.get_instance_utilization(
                instance)
            node_cpu_util += instance_util['cpu']
            node_ram_util += instance_util['ram']
            node_disk_util += instance_util['disk']

        return dict(cpu=node_cpu_util, ram=node_ram_util,
                    disk=node_disk_util)

    def get_node_capacity(self, node):
        """Collect cpu, ram and disk capacity of a node.

        :param node: node object
        :return: dict(cpu(cores), ram(MB), disk(B))
        """
        return dict(cpu=node.vcpu_capacity, ram=node.memory_mb_capacity,
                    disk=node.disk_gb_capacity)

    def get_relative_node_utilization(self, node):
        """Return relative node utilization.

        :param node: node object
        :return: {'cpu': <0,1>, 'ram': <0,1>, 'disk': <0,1>}
        """
        relative_node_utilization = {}
        util = self.get_node_utilization(node)
        cap = self.get_node_capacity(node)
        for k in util.keys():
            relative_node_utilization[k] = float(util[k]) / float(cap[k])
        return relative_node_utilization

    def get_relative_cluster_utilization(self):
        """Calculate relative cluster utilization (rcu).

        RCU is an average of relative utilizations (rhu) of active nodes.
        :return: {'cpu': <0,1>, 'ram': <0,1>, 'disk': <0,1>}
        """
        nodes = self.get_available_compute_nodes().values()
        rcu = {}
        counters = {}
        for node in nodes:
            node_status_str = self.get_node_status_str(node)
            if node_status_str == element.ServiceState.ENABLED.value:
                rhu = self.get_relative_node_utilization(node)
                for k in rhu.keys():
                    if k not in rcu:
                        rcu[k] = 0
                    if k not in counters:
                        counters[k] = 0
                    rcu[k] += rhu[k]
                    counters[k] += 1
        for k in rcu.keys():
            rcu[k] /= counters[k]
        return rcu

    def is_overloaded(self, node, cc):
        """Indicate whether a node is overloaded.

        This considers provided resource capacity coefficients (cc).
        :param node: node object
        :param cc: dictionary containing resource capacity coefficients
        :return: [True, False]
        """
        node_capacity = self.get_node_capacity(node)
        node_utilization = self.get_node_utilization(
            node)
        metrics = ['cpu']
        for m in metrics:
            if node_utilization[m] > node_capacity[m] * cc[m]:
                return True
        return False

    def instance_fits(self, instance, node, cc):
        """Indicate whether is a node able to accommodate a VM.

        This considers provided resource capacity coefficients (cc).
        :param instance: :py:class:`~.element.Instance`
        :param node: node object
        :param cc: dictionary containing resource capacity coefficients
        :return: [True, False]
        """
        node_capacity = self.get_node_capacity(node)
        node_utilization = self.get_node_utilization(node)
        instance_utilization = self.get_instance_utilization(instance)
        metrics = ['cpu', 'ram', 'disk']
        for m in metrics:
            if (instance_utilization[m] + node_utilization[m] >
                    node_capacity[m] * cc[m]):
                return False
        return True

    def optimize_solution(self):
        """Optimize solution.

        This is done by eliminating unnecessary or circular set of migrations
        which can be replaced by a more efficient solution.
        e.g.:

        * A->B, B->C => replace migrations A->B, B->C with
          a single migration A->C as both solution result in
          VM running on node C which can be achieved with
          one migration instead of two.
        * A->B, B->A => remove A->B and B->A as they do not result
          in a new VM placement.
        """
        migrate_actions = (
            a for a in self.solution.actions if a[
                'action_type'] == self.MIGRATION)
        instance_to_be_migrated = (
            a['input_parameters']['resource_id'] for a in migrate_actions)
        instance_uuids = list(set(instance_to_be_migrated))
        for instance_uuid in instance_uuids:
            actions = list(
                a for a in self.solution.actions if a[
                    'input_parameters'][
                        'resource_id'] == instance_uuid)
            if len(actions) > 1:
                src_name = actions[0]['input_parameters']['source_node']
                dst_name = actions[-1]['input_parameters']['destination_node']
                for a in actions:
                    self.solution.actions.remove(a)
                    self.number_of_migrations -= 1
                src_node = self.compute_model.get_node_by_name(src_name)
                dst_node = self.compute_model.get_node_by_name(dst_name)
                instance = self.compute_model.get_instance_by_uuid(
                    instance_uuid)
                if self.compute_model.migrate_instance(
                        instance, dst_node, src_node):
                    self.add_migration(instance, src_node, dst_node)

    def offload_phase(self, cc):
        """Perform offloading phase.

        This considers provided resource capacity coefficients.
        Offload phase performing first-fit based bin packing to offload
        overloaded nodes. This is done in a fashion of moving
        the least CPU utilized VM first as live migration these
        generally causes less troubles. This phase results in a cluster
        with no overloaded nodes.
        * This phase is be able to enable disabled nodes (if needed
        and any available) in the case of the resource capacity provided by
        active nodes is not able to accommodate all the load.
        As the offload phase is later followed by the consolidation phase,
        the node enabler in this phase doesn't necessarily results
        in more enabled nodes in the final solution.

        :param cc: dictionary containing resource capacity coefficients
        """
        sorted_nodes = sorted(
            self.get_available_compute_nodes().values(),
            key=lambda x: self.get_node_utilization(x)['cpu'])
        for node in reversed(sorted_nodes):
            if self.is_overloaded(node, cc):
                for instance in sorted(
                        self.compute_model.get_node_instances(node),
                        key=lambda x: self.get_instance_utilization(
                            x)['cpu']
                ):
                    # skip exclude instance when migrating
                    if instance.watcher_exclude:
                        LOG.debug("Instance is excluded by scope, "
                                  "skipped: %s", instance.uuid)
                        continue
                    for destination_node in reversed(sorted_nodes):
                        if self.instance_fits(
                                instance, destination_node, cc):
                            self.add_migration(instance, node,
                                               destination_node)
                            break
                    if not self.is_overloaded(node, cc):
                        break

    def consolidation_phase(self, cc):
        """Perform consolidation phase.

        This considers provided resource capacity coefficients.
        Consolidation phase performing first-fit based bin packing.
        First, nodes with the lowest cpu utilization are consolidated
        by moving their load to nodes with the highest cpu utilization
        which can accommodate the load. In this phase the most cpu utilized
        VMs are prioritized as their load is more difficult to accommodate
        in the system than less cpu utilized VMs which can be later used
        to fill smaller CPU capacity gaps.

        :param cc: dictionary containing resource capacity coefficients
        """
        sorted_nodes = sorted(
            self.get_available_compute_nodes().values(),
            key=lambda x: self.get_node_utilization(x)['cpu'])
        asc = 0
        for node in sorted_nodes:
            instances = sorted(
                self.compute_model.get_node_instances(node),
                key=lambda x: self.get_instance_utilization(x)['cpu'])
            for instance in reversed(instances):
                # skip exclude instance when migrating
                if instance.watcher_exclude:
                    LOG.debug("Instance is excluded by scope, "
                              "skipped: %s", instance.uuid)
                    continue
                dsc = len(sorted_nodes) - 1
                for destination_node in reversed(sorted_nodes):
                    if asc >= dsc:
                        break
                    if self.instance_fits(
                            instance, destination_node, cc):
                        self.add_migration(instance, node,
                                           destination_node)
                        break
                    dsc -= 1
            asc += 1

    def pre_execute(self):
        self._pre_execute()

    def do_execute(self, audit=None):
        """Execute strategy.

        This strategy produces a solution resulting in more
        efficient utilization of cluster resources using following
        four phases:

        * Offload phase - handling over-utilized resources
        * Consolidation phase - handling under-utilized resources
        * Solution optimization - reducing number of migrations
        * Disability of unused nodes

        :param original_model: root_model object
        """
        LOG.info('Executing Smart Strategy')
        rcu = self.get_relative_cluster_utilization()

        cc = {'cpu': 1.0, 'ram': 1.0, 'disk': 1.0}

        # Offloading phase
        self.offload_phase(cc)

        # Consolidation phase
        self.consolidation_phase(cc)

        # Optimize solution
        self.optimize_solution()

        # disable unused nodes
        self.disable_unused_nodes()

        rcu_after = self.get_relative_cluster_utilization()
        info = {
            "compute_nodes_count": len(
                self.get_available_compute_nodes()),
            'number_of_migrations': self.number_of_migrations,
            'number_of_released_nodes':
                self.number_of_released_nodes,
            'relative_cluster_utilization_before': str(rcu),
            'relative_cluster_utilization_after': str(rcu_after)
        }

        LOG.debug(info)

    def post_execute(self):
        self.solution.set_efficacy_indicators(
            compute_nodes_count=len(
                self.get_available_compute_nodes()),
            released_compute_nodes_count=self.number_of_released_nodes,
            instance_migrations_count=self.number_of_migrations,
        )

        LOG.debug(self.compute_model.to_string())