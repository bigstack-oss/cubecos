# -*- encoding: utf-8 -*-
# Copyright (c) 2019  ZTE Corporation
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
from watcher import objects

LOG = log.getLogger(__name__)


class NodeResourceConsolidation(base.ServerConsolidationBaseStrategy):
    """consolidating resources on nodes using server migration

    *Description*

    This strategy checks the resource usages of compute nodes, if the used
    resources are less than total, it will try to migrate server to
    consolidate the use of resource.

    *Requirements*

    * You must have at least 2 compute nodes to run
      this strategy.
    * Hardware: compute nodes should use the same physical CPUs/RAMs

    *Limitations*

    * This is a proof of concept that is not meant to be used in production
    * It assume that live migrations are possible

    *Spec URL*

    http://specs.openstack.org/openstack/watcher-specs/specs/train/implemented/node-resource-consolidation.html
    """

    CHANGE_NOVA_SERVICE_STATE = "change_nova_service_state"
    REASON_FOR_DISABLE = 'Watcher node resource consolidation strategy'

    def __init__(self, config, osc=None):
        """node resource consolidation

        :param config: A mapping containing the configuration of this strategy
        :type config: :py:class:`~.Struct` instance
        :param osc: :py:class:`~.OpenStackClients` instance
        """
        super(NodeResourceConsolidation, self).__init__(config, osc)
        self.host_choice = 'auto'
        self.audit = None
        self.compute_nodes_count = 0
        self.number_of_released_nodes = 0
        self.number_of_migrations = 0

    @classmethod
    def get_name(cls):
        return "node_resource_consolidation"

    @classmethod
    def get_display_name(cls):
        return _("Node Resource Consolidation strategy")

    @classmethod
    def get_translatable_display_name(cls):
        return "Node Resource Consolidation strategy"

    @classmethod
    def get_schema(cls):
        # Mandatory default setting for each element
        return {
            "properties": {
                "host_choice": {
                    "description": "The way to select the server migration "
                                   "destination node. The value 'auto' "
                                   "means that Nova scheduler selects "
                                   "the destination node, and 'specify' "
                                   "means the strategy specifies the "
                                   "destination.",
                    "type": "string",
                    "default": 'auto'
                },
            },
        }

    def check_resources(self, servers, destination):
        # check whether a node able to accommodate a VM
        dest_flag = False
        if not destination:
            return dest_flag
        free_res = self.compute_model.get_node_free_resources(destination)
        for server in servers:
            # just vcpu and memory, do not consider disk
            if free_res['vcpu'] >= server.vcpus and (
                    free_res['memory'] >= server.memory):
                free_res['vcpu'] -= server.vcpus
                free_res['memory'] -= server.memory
                dest_flag = True
                servers.remove(server)

        return dest_flag

    def select_destination(self, server, source, destinations):
        dest_node = None
        if not destinations:
            return dest_node
        sorted_nodes = sorted(
            destinations,
            key=lambda x: self.compute_model.get_node_free_resources(
                x)['vcpu'])
        for dest in sorted_nodes:
            if self.check_resources([server], dest):
                if self.compute_model.migrate_instance(server, source, dest):
                    dest_node = dest
                    break

        return dest_node

    def add_migrate_actions(self, sources, destinations):
        if not sources or not destinations:
            return
        for node in sources:
            servers = self.compute_model.get_node_instances(node)
            sorted_servers = sorted(
                servers,
                key=lambda x: x.vcpus,
                reverse=True)
            for server in sorted_servers:
                parameters = {'migration_type': 'live',
                              'source_node': node.hostname,
                              'resource_name': server.name}
                action_flag = False
                if self.host_choice != 'auto':
                    # specify destination host
                    dest = self.select_destination(server, node, destinations)
                    if dest:
                        parameters['destination_node'] = dest.hostname
                        action_flag = True
                else:
                    action_flag = True
                if action_flag:
                    self.number_of_migrations += 1
                    self.solution.add_action(
                        action_type=self.MIGRATION,
                        resource_id=server.uuid,
                        input_parameters=parameters)

    def add_change_node_state_actions(self, nodes, status):
        if status not in (element.ServiceState.DISABLED.value,
                          element.ServiceState.ENABLED.value):
            raise exception.IllegalArgumentException(
                message=_("The node status is not defined"))
        changed_nodes = []
        for node in nodes:
            if node.status != status:
                parameters = {'state': status,
                              'resource_name': node.hostname}
                if status == element.ServiceState.DISABLED.value:
                    parameters['disabled_reason'] = self.REASON_FOR_DISABLE
                self.solution.add_action(
                    action_type=self.CHANGE_NOVA_SERVICE_STATE,
                    resource_id=node.uuid,
                    input_parameters=parameters)
                node.status = status
                changed_nodes.append(node)

        return changed_nodes

    def get_nodes_migrate_failed(self):
        # check if migration action ever failed
        # just for continuous audit
        nodes_failed = []
        if self.audit is None or (
                self.audit.audit_type ==
                objects.audit.AuditType.ONESHOT.value):
            return nodes_failed
        filters = {'audit_uuid': self.audit.uuid}
        actions = objects.action.Action.list(
            self.ctx,
            filters=filters)
        for action in actions:
            if action.state == objects.action.State.FAILED and (
                    action.action_type == self.MIGRATION):
                server_uuid = action.input_parameters.get('resource_id')
                node = self.compute_model.get_node_by_instance_uuid(
                    server_uuid)
                if node not in nodes_failed:
                    nodes_failed.append(node)

        return nodes_failed

    def group_nodes(self, nodes):
        free_nodes = []
        source_nodes = []
        dest_nodes = []
        nodes_failed = self.get_nodes_migrate_failed()
        LOG.info("nodes: %s migration failed", nodes_failed)
        sorted_nodes = sorted(
            nodes,
            key=lambda x: self.compute_model.get_node_used_resources(
                x)['vcpu'])
        for node in sorted_nodes:
            if node in dest_nodes:
                break
            # If ever migration failed, do not migrate again
            if node in nodes_failed:
                # maybe can as the destination node
                if node.status == element.ServiceState.ENABLED.value:
                    dest_nodes.append(node)
                continue
            used_resource = self.compute_model.get_node_used_resources(node)
            if used_resource['vcpu'] > 0:
                servers = self.compute_model.get_node_instances(node)
                for dest in reversed(sorted_nodes):
                    # skip if compute node is disabled
                    if dest.status == element.ServiceState.DISABLED.value:
                        LOG.info("node %s is down", dest.hostname)
                        continue
                    if dest in dest_nodes:
                        continue
                    if node == dest:
                        # The last on as destination node
                        dest_nodes.append(dest)
                        break
                    if self.check_resources(servers, dest):
                        dest_nodes.append(dest)
                        if node not in source_nodes:
                            source_nodes.append(node)
                    if not servers:
                        break
            else:
                free_nodes.append(node)

        return free_nodes, source_nodes, dest_nodes

    def pre_execute(self):
        self._pre_execute()
        self.host_choice = self.input_parameters.get('host_choice', 'auto')
        self.planner = 'node_resource_consolidation'

    def do_execute(self, audit=None):
        """Strategy execution phase

        Executing strategy and creating solution.
        """
        self.audit = audit
        nodes = list(self.compute_model.get_all_compute_nodes().values())
        free_nodes, source_nodes, dest_nodes = self.group_nodes(nodes)
        self.compute_nodes_count = len(nodes)
        self.number_of_released_nodes = len(source_nodes)
        LOG.info("Free nodes: %s", free_nodes)
        LOG.info("Source nodes: %s", source_nodes)
        LOG.info("Destination nodes: %s", dest_nodes)
        if not source_nodes:
            LOG.info("No compute node needs to be consolidated")
            return
        nodes_disabled = []
        if self.host_choice == 'auto':
            # disable compute node to avoid to be select by Nova scheduler
            nodes_disabled = self.add_change_node_state_actions(
                free_nodes+source_nodes, element.ServiceState.DISABLED.value)
        self.add_migrate_actions(source_nodes, dest_nodes)
        if nodes_disabled:
            # restore disabled compute node after migration
            self.add_change_node_state_actions(
                nodes_disabled, element.ServiceState.ENABLED.value)

    def post_execute(self):
        """Post-execution phase

        """
        self.solution.set_efficacy_indicators(
            compute_nodes_count=self.compute_nodes_count,
            released_compute_nodes_count=self.number_of_released_nodes,
            instance_migrations_count=self.number_of_migrations,
        )
