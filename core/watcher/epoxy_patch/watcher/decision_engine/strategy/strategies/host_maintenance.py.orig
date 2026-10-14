# -*- encoding: utf-8 -*-
# Copyright (c) 2017 chinac.com
#
# Authors: suzhengwei<suzhengwei@chinac.com>
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


class HostMaintenance(base.HostMaintenanceBaseStrategy):
    """[PoC]Host Maintenance

    *Description*

        It is a migration strategy for one compute node maintenance,
        without having the user's application been interrupted.
        If given one backup node, the strategy will firstly
        migrate all instances from the maintenance node to
        the backup node. If the backup node is not provided,
        it will migrate all instances, relying on nova-scheduler.

    *Requirements*

        * You must have at least 2 physical compute nodes to run this strategy.

    *Limitations*

       - This is a proof of concept that is not meant to be used in production
       - It migrates all instances from one host to other hosts. It's better to
         execute such strategy when load is not heavy, and use this algorithm
         with `ONESHOT` audit.
       - It assumes that cold and live migrations are possible.
    """

    INSTANCE_MIGRATION = "migrate"
    CHANGE_NOVA_SERVICE_STATE = "change_nova_service_state"

    def __init__(self, config, osc=None):
        super(HostMaintenance, self).__init__(config, osc)

    @classmethod
    def get_name(cls):
        return "host_maintenance"

    @classmethod
    def get_display_name(cls):
        return _("Host Maintenance Strategy")

    @classmethod
    def get_translatable_display_name(cls):
        return "Host Maintenance Strategy"

    @classmethod
    def get_schema(cls):
        return {
            "properties": {
                "maintenance_node": {
                    "description": "The name of the compute node which "
                                   "need maintenance",
                    "type": "string",
                },
                "backup_node": {
                    "description": "The name of the compute node which "
                                   "will backup the maintenance node.",
                    "type": "string",
                },
            },
            "required": ["maintenance_node"],
        }

    def get_disabled_compute_nodes_with_reason(self, reason=None):
        return {uuid: cn for uuid, cn in
                self.compute_model.get_all_compute_nodes().items()
                if cn.state == element.ServiceState.ONLINE.value and
                cn.status == element.ServiceState.DISABLED.value and
                cn.disabled_reason == reason}

    def get_instance_state_str(self, instance):
        """Get instance state in string format"""
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
        """Get node status in string format"""
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

    def get_node_capacity(self, node):
        """Collect cpu, ram and disk capacity of a node.

        :param node: node object
        :return: dict(cpu(cores), ram(MB), disk(B))
        """
        return dict(cpu=node.vcpu_capacity,
                    ram=node.memory_mb_capacity,
                    disk=node.disk_gb_capacity)

    def host_fits(self, source_node, destination_node):
        """check host fits

        return True if VMs could intensively migrate
        from source_node to destination_node.
        """

        source_node_used = self.compute_model.get_node_used_resources(
            source_node)
        destination_node_free = self.compute_model.get_node_free_resources(
            destination_node)
        metrics = ['vcpu', 'memory']
        for m in metrics:
            if source_node_used[m] > destination_node_free[m]:
                return False
        return True

    def add_action_enable_compute_node(self, node):
        """Add an action for node enabler into the solution."""
        params = {'state': element.ServiceState.ENABLED.value,
                  'resource_name': node.hostname}
        self.solution.add_action(
            action_type=self.CHANGE_NOVA_SERVICE_STATE,
            resource_id=node.uuid,
            input_parameters=params)

    def add_action_maintain_compute_node(self, node):
        """Add an action for node maintenance into the solution."""
        params = {'state': element.ServiceState.DISABLED.value,
                  'disabled_reason': self.REASON_FOR_MAINTAINING,
                  'resource_name': node.hostname}
        self.solution.add_action(
            action_type=self.CHANGE_NOVA_SERVICE_STATE,
            resource_id=node.uuid,
            input_parameters=params)

    def enable_compute_node_if_disabled(self, node):
        node_status_str = self.get_node_status_str(node)
        if node_status_str != element.ServiceState.ENABLED.value:
            self.add_action_enable_compute_node(node)

    def instance_migration(self, instance, src_node, des_node=None):
        """Add an action for instance migration into the solution.

        :param instance: instance object
        :param src_node: node object
        :param des_node: node object. if None, the instance will be
            migrated relying on nova-scheduler
        :return: None
        """
        instance_state_str = self.get_instance_state_str(instance)
        if instance_state_str == element.InstanceState.ACTIVE.value:
            migration_type = 'live'
        else:
            migration_type = 'cold'

        params = {'migration_type': migration_type,
                  'source_node': src_node.uuid,
                  'resource_name': instance.name}
        if des_node:
            params['destination_node'] = des_node.hostname
        self.solution.add_action(action_type=self.INSTANCE_MIGRATION,
                                 resource_id=instance.uuid,
                                 input_parameters=params)

    def host_migration(self, source_node, destination_node):
        """host migration

        Migrate all instances from source_node to destination_node.
        Active instances use "live-migrate",
        and other instances use "cold-migrate"
        """
        instances = self.compute_model.get_node_instances(source_node)
        for instance in instances:
            self.instance_migration(instance, source_node, destination_node)

    def safe_maintain(self, maintenance_node, backup_node=None):
        """safe maintain one compute node

        Migrate all instances of the maintenance_node intensively to the
        backup host.

        It calculate the resource both of the backup node and maintaining
        node to evaluate the migrations from maintaining node to backup node.
        If all instances of the maintaining node can migrated to
        the backup node, it will set the maintaining node in
        'watcher_maintaining' status, and add the migrations to solution.
        """
        # If the user gives a backup node with required capacity, then migrates
        # all instances from the maintaining node to the backup node.
        if backup_node:
            if self.host_fits(maintenance_node, backup_node):
                self.enable_compute_node_if_disabled(backup_node)
                self.add_action_maintain_compute_node(maintenance_node)
                self.host_migration(maintenance_node, backup_node)
                return True

        return False

    def try_maintain(self, maintenance_node):
        """try to maintain one compute node

        It firstly set the maintenance_node in 'watcher_maintaining' status.
        Then try to migrate all instances of the maintenance node, rely
        on nova-scheduler.
        """
        self.add_action_maintain_compute_node(maintenance_node)
        instances = self.compute_model.get_node_instances(maintenance_node)
        for instance in instances:
            self.instance_migration(instance, maintenance_node)

    def pre_execute(self):
        self._pre_execute()

    def do_execute(self, audit=None):
        LOG.info(_('Executing Host Maintenance Migration Strategy'))

        maintenance_node = self.input_parameters.get('maintenance_node')
        backup_node = self.input_parameters.get('backup_node')

        # if no VMs in the maintenance_node, just maintain the compute node
        src_node = self.compute_model.get_node_by_name(maintenance_node)
        if len(self.compute_model.get_node_instances(src_node)) == 0:
            if (src_node.disabled_reason !=
                    self.REASON_FOR_MAINTAINING):
                self.add_action_maintain_compute_node(src_node)
                return

        if backup_node:
            des_node = self.compute_model.get_node_by_name(backup_node)
        else:
            des_node = None

        if not self.safe_maintain(src_node, des_node):
            self.try_maintain(src_node)

    def post_execute(self):
        """Post-execution phase

        This can be used to compute the global efficacy
        """
        LOG.debug(self.solution.actions)
        LOG.debug(self.compute_model.to_string())
