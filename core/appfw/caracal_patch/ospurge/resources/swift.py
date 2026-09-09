#  Licensed under the Apache License, Version 2.0 (the "License"); you may
#  not use this file except in compliance with the License. You may obtain
#  a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#  License for the specific language governing permissions and limitations
#  under the License.
from ospurge.resources import base
from ospurge.resources.base import BaseServiceResource
from ospurge.resources import glance


class ListObjectsMixin(BaseServiceResource):
    def list_objects(self):
        for container in self.cloud.list_containers():
            for obj in self.cloud.list_objects(container['name']):
                # Upstream assigns obj['container_name'] = container['name']
                # here. openstacksdk 1.0 made Resource.__setitem__ reject keys
                # that are not declared components, so that raises
                # KeyError("container_name is not found. ...Object objects do
                # not support setting arbitrary keys through the dict
                # interface") and ospurge logs "Can't deal with Objects" and
                # skips every object. The container name no longer has to be
                # carried by hand: the same 1.0 series added a 'container'
                # field, which list_objects() populates, so the two readers
                # below use that instead.
                yield obj


class Objects(base.ServiceResource, glance.ListImagesMixin, ListObjectsMixin):
    ORDER = 73

    def check_prerequisite(self):
        return (self.list_images_by_owner() == [] and
                self.cloud.list_volume_backups() == [])

    def list(self):
        for item in self.list_objects():
            yield item

    def delete(self, resource):
        self.cloud.delete_object(resource['container'], resource['name'])

    @staticmethod
    def to_str(resource):
        return "Object '{}' from Container '{}'".format(
            resource['name'], resource['container'])


class Containers(base.ServiceResource, ListObjectsMixin):
    ORDER = 75

    def check_prerequisite(self):
        return list(self.list_objects()) == []

    def list(self):
        return self.cloud.list_containers()

    def delete(self, resource):
        self.cloud.delete_container(resource['name'])

    def disable(self, resource):
        # There is no disable for the swift container just removing the
        # write/read access to the container, so only admin can access
        self.cloud.object_store.set_container_metadata(
            resource['name'], write_acl=None, read_acl=None
        )

    @staticmethod
    def to_str(resource):
        return "Container (name='{}')".format(resource['name'])
