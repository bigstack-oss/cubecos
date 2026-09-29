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


class Stacks(base.ServiceResource):
    ORDER = 10

    def list(self):
        if not self.cloud.has_service('orchestration'):
            return []
        return self.cloud.list_stacks()

    def delete(self, resource):
        self.cloud.delete_stack(resource['id'], wait=True)

    @staticmethod
    def to_str(resource):
        return "Heat Stack (id='{}', name='{}'".format(
            resource['id'], resource['name'])
