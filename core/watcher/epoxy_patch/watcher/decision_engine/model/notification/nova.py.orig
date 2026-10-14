# -*- encoding: utf-8 -*-
# Copyright (c) 2016 b<>com
#
# Authors: Vincent FRANCOISE <Vincent.FRANCOISE@b-com.com>
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

import os_resource_classes as orc
from oslo_log import log
from watcher.common import exception
from watcher.common import nova_helper
from watcher.common import placement_helper
from watcher.common import utils
from watcher.decision_engine.model import element
from watcher.decision_engine.model.notification import base
from watcher.decision_engine.model.notification import filtering

LOG = log.getLogger(__name__)


class NovaNotification(base.NotificationEndpoint):

    def __init__(self, collector):
        super(NovaNotification, self).__init__(collector)
        self._nova = None
        self._placement_helper = None

    @property
    def nova(self):
        if self._nova is None:
            self._nova = nova_helper.NovaHelper()
        return self._nova

    @property
    def placement_helper(self):
        if self._placement_helper is None:
            self._placement_helper = placement_helper.PlacementHelper()
        return self._placement_helper

    def get_or_create_instance(self, instance_uuid, node_name=None):
        try:
            node = None
            if node_name:
                node = self.get_or_create_node(node_name)
        except exception.ComputeNodeNotFound:
            LOG.warning("Could not find compute node %(node)s for "
                        "instance %(instance)s",
                        dict(node=node_name, instance=instance_uuid))
        try:
            instance = self.cluster_data_model.get_instance_by_uuid(
                instance_uuid)
        except exception.InstanceNotFound:
            # The instance didn't exist yet so we create a new instance object
            LOG.debug("New instance created: %s", instance_uuid)
            instance = element.Instance(uuid=instance_uuid)

            self.cluster_data_model.add_instance(instance)
            if node:
                self.cluster_data_model.map_instance(instance, node)

        return instance

    def update_instance(self, instance, data):
        n_version = float(data['nova_object.version'])
        instance_data = data['nova_object.data']
        instance_flavor_data = instance_data['flavor']['nova_object.data']

        memory_mb = instance_flavor_data['memory_mb']
        num_cores = instance_flavor_data['vcpus']
        disk_gb = instance_flavor_data['root_gb']
        instance_metadata = data['nova_object.data']['metadata']

        instance.update({
            'state': instance_data['state'],
            'hostname': instance_data['host_name'],
            # this is the user-provided display name of the server which is not
            # guaranteed to be unique nor is it immutable.
            'name': instance_data['display_name'],
            'memory': memory_mb,
            'vcpus': num_cores,
            'disk': disk_gb,
            'metadata': instance_metadata,
            'project_id': instance_data['tenant_id']
        })
        # locked was added in nova notification payload version 1.1
        if n_version > 1.0:
            instance.update({'locked': instance_data['locked']})

        try:
            node = self.get_or_create_node(instance_data['host'])
        except exception.ComputeNodeNotFound as exc:
            LOG.exception(exc)
            # If we can't create the node, we consider the instance as unmapped
            node = None

        self.update_instance_mapping(instance, node)

    def update_compute_node(self, node, data):
        """Update the compute node using the notification data."""
        node_data = data['nova_object.data']
        node_state = (
            element.ServiceState.OFFLINE.value
            if node_data['forced_down'] else element.ServiceState.ONLINE.value)
        node_status = (
            element.ServiceState.DISABLED.value
            if node_data['disabled'] else element.ServiceState.ENABLED.value)
        disabled_reason = (
            node_data['disabled_reason']
            if node_data['disabled'] else None)

        node.update({
            'hostname': node_data['host'],
            'state': node_state,
            'status': node_status,
            'disabled_reason': disabled_reason,
        })

    def create_compute_node(self, uuid_or_name):
        """Create the computeNode node."""
        try:
            if utils.is_uuid_like(uuid_or_name):
                _node = self.nova.get_compute_node_by_uuid(uuid_or_name)
            else:
                _node = self.nova.get_compute_node_by_hostname(uuid_or_name)
            inventories = self.placement_helper.get_inventories(_node.id)
            if inventories and orc.VCPU in inventories:
                vcpus = inventories[orc.VCPU]['total']
                vcpu_reserved = inventories[orc.VCPU]['reserved']
                vcpu_ratio = inventories[orc.VCPU]['allocation_ratio']
            else:
                vcpus = _node.vcpus
                vcpu_reserved = 0
                vcpu_ratio = 1.0

            if inventories and orc.MEMORY_MB in inventories:
                memory_mb = inventories[orc.MEMORY_MB]['total']
                memory_mb_reserved = inventories[orc.MEMORY_MB]['reserved']
                memory_ratio = inventories[orc.MEMORY_MB]['allocation_ratio']
            else:
                memory_mb = _node.memory_mb
                memory_mb_reserved = 0
                memory_ratio = 1.0

            # NOTE(licanwei): A BP support-shared-storage-resource-provider
            # will move DISK_GB from compute node to shared storage RP.
            # Here may need to be updated when the nova BP released.
            if inventories and orc.DISK_GB in inventories:
                disk_capacity = inventories[orc.DISK_GB]['total']
                disk_gb_reserved = inventories[orc.DISK_GB]['reserved']
                disk_ratio = inventories[orc.DISK_GB]['allocation_ratio']
            else:
                disk_capacity = _node.local_gb
                disk_gb_reserved = 0
                disk_ratio = 1.0

            # build up the compute node.
            node_attributes = {
                # The id of the hypervisor as a UUID from version 2.53.
                "uuid": _node.id,
                "hostname": _node.service["host"],
                "memory": memory_mb,
                "memory_ratio": memory_ratio,
                "memory_mb_reserved": memory_mb_reserved,
                "disk": disk_capacity,
                "disk_gb_reserved": disk_gb_reserved,
                "disk_ratio": disk_ratio,
                "vcpus": vcpus,
                "vcpu_reserved": vcpu_reserved,
                "vcpu_ratio": vcpu_ratio,
                "state": _node.state,
                "status": _node.status,
                "disabled_reason": _node.service["disabled_reason"]}

            node = element.ComputeNode(**node_attributes)
            self.cluster_data_model.add_node(node)
            LOG.debug("New compute node mapped: %s", node.uuid)
            return node
        except Exception as exc:
            LOG.exception(exc)
            LOG.debug("Could not refresh the node %s.", uuid_or_name)
            raise exception.ComputeNodeNotFound(name=uuid_or_name)

    def get_or_create_node(self, uuid_or_name):
        if uuid_or_name is None:
            LOG.debug("Compute node UUID or name not provided: skipping")
            return
        try:
            if utils.is_uuid_like(uuid_or_name):
                return self.cluster_data_model.get_node_by_uuid(uuid_or_name)
            else:
                return self.cluster_data_model.get_node_by_name(uuid_or_name)
        except exception.ComputeNodeNotFound:
            # The node didn't exist yet so we create a new node object
            node = self.create_compute_node(uuid_or_name)
            LOG.debug("New compute node created: %s", uuid_or_name)
            return node

    def update_instance_mapping(self, instance, node):
        if node is None:
            self.cluster_data_model.add_instance(instance)
            LOG.debug("Instance %s not yet attached to any node: skipping",
                      instance.uuid)
            return
        try:
            try:
                current_node = (
                    self.cluster_data_model.get_node_by_instance_uuid(
                        instance.uuid))
            except exception.ComputeResourceNotFound as exc:
                LOG.exception(exc)
                # If we can't create the node,
                # we consider the instance as unmapped
                current_node = None

            LOG.debug("Mapped node %s found", node.uuid)
            if current_node and node != current_node:
                LOG.debug("Unmapping instance %s from %s",
                          instance.uuid, node.uuid)
                self.cluster_data_model.unmap_instance(instance, current_node)
        except exception.InstanceNotFound:
            # The instance didn't exist yet so we map it for the first time
            LOG.debug("New instance: mapping it to %s", node.uuid)
        finally:
            if node:
                self.cluster_data_model.map_instance(instance, node)
                LOG.debug("Mapped instance %s to %s", instance.uuid, node.uuid)

    def delete_instance(self, instance, node):
        try:
            self.cluster_data_model.delete_instance(instance, node)
        except Exception:
            LOG.info("Instance %s already deleted", instance.uuid)

    def delete_node(self, node):
        try:
            self.cluster_data_model.remove_node(node)
        except Exception:
            LOG.info("Node %s already deleted", node.uuid)


class VersionedNotification(NovaNotification):
    publisher_id_regex = r'^nova-.*'

    def service_updated(self, payload):
        node_data = payload['nova_object.data']
        node_name = node_data['host']
        try:
            node = self.get_or_create_node(node_name)
            self.update_compute_node(node, payload)
        except exception.ComputeNodeNotFound as exc:
            LOG.exception(exc)

    def service_deleted(self, payload):
        node_data = payload['nova_object.data']
        node_name = node_data['host']
        try:
            node = self.get_or_create_node(node_name)
            self.delete_node(node)
        except exception.ComputeNodeNotFound as exc:
            LOG.exception(exc)

    def instance_updated(self, payload):
        instance_data = payload['nova_object.data']
        instance_uuid = instance_data['uuid']
        instance_state = instance_data['state']
        node_name = instance_data.get('host')
        # if instance state is building, don't update data model
        if instance_state == 'building':
            return

        instance = self.get_or_create_instance(instance_uuid, node_name)

        self.update_instance(instance, payload)

    def instance_created(self, payload):
        instance_data = payload['nova_object.data']
        instance_uuid = instance_data['uuid']
        instance = element.Instance(uuid=instance_uuid)
        self.cluster_data_model.add_instance(instance)

        node_name = instance_data.get('host')
        if node_name:
            node = self.get_or_create_node(node_name)
            self.cluster_data_model.map_instance(instance, node)

        self.update_instance(instance, payload)

    def instance_deleted(self, payload):
        instance_data = payload['nova_object.data']
        instance_uuid = instance_data['uuid']
        node_name = instance_data.get('host')
        instance = self.get_or_create_instance(instance_uuid, node_name)

        try:
            node = self.get_or_create_node(instance_data['host'])
        except exception.ComputeNodeNotFound as exc:
            LOG.exception(exc)
            # If we can't create the node, we consider the instance as unmapped
            node = None

        self.delete_instance(instance, node)

    notification_mapping = {
        'instance.create.end': instance_created,
        'instance.lock': instance_updated,
        'instance.unlock': instance_updated,
        'instance.pause.end': instance_updated,
        'instance.power_off.end': instance_updated,
        'instance.power_on.end': instance_updated,
        'instance.resize_confirm.end': instance_updated,
        'instance.restore.end': instance_updated,
        'instance.resume.end': instance_updated,
        'instance.shelve.end': instance_updated,
        'instance.shutdown.end': instance_updated,
        'instance.suspend.end': instance_updated,
        'instance.unpause.end': instance_updated,
        'instance.unrescue.end': instance_updated,
        'instance.unshelve.end': instance_updated,
        'instance.rebuild.end': instance_updated,
        'instance.rescue.end': instance_updated,
        'instance.update': instance_updated,
        'instance.live_migration_force_complete.end': instance_updated,
        'instance.live_migration_post.end': instance_updated,
        'instance.delete.end': instance_deleted,
        'instance.soft_delete.end': instance_deleted,
        'service.create': service_updated,
        'service.delete': service_deleted,
        'service.update': service_updated,
        }

    @property
    def filter_rule(self):
        """Nova notification filter"""
        return filtering.NotificationFilter(
            publisher_id=self.publisher_id_regex,
        )

    def info(self, ctxt, publisher_id, event_type, payload, metadata):
        LOG.info("Event '%(event)s' received from %(publisher)s "
                 "with metadata %(metadata)s",
                 dict(event=event_type,
                      publisher=publisher_id,
                      metadata=metadata))
        func = self.notification_mapping.get(event_type)
        if func:
            # The nova CDM is not built until an audit is performed.
            if self.cluster_data_model:
                LOG.debug(payload)
                func(self, payload)
            else:
                LOG.debug('Nova CDM has not yet been built; ignoring '
                          'notifications until an audit is performed.')
