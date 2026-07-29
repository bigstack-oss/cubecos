# Copyright(c) 2016 Nippon Telegraph and Telephone Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import eventlet
from keystoneauth1 import loading as ks_loading
from openstack import connection
from openstack import exceptions
from oslo_log import log as oslo_logging

import masakarimonitors.conf

LOG = oslo_logging.getLogger(__name__)
CONF = masakarimonitors.conf.CONF


class SendNotification(object):

    def __init__(self):
        self._masakari_client = None

    @property
    def masakari_client(self):
        if not self._masakari_client:
            self._masakari_client = self._make_client()
        return self._masakari_client

    def _make_client(self):
        auth = ks_loading.load_auth_from_conf_options(CONF, 'api')
        session = ks_loading.load_session_from_conf_options(CONF, 'api',
                                                            auth=auth)
        conn = connection.Connection(session=session,
                                     interface=CONF.api.api_interface,
                                     region_name=CONF.api.region)

        return conn.instance_ha

    def send_notification(self, api_retry_max, api_retry_interval, event):
        """Send a notification.

        This method sends a notification to the masakari-api.

        :param api_retry_max: Number of retries when the notification
            processing is error.
        :param api_retry_interval: Trial interval of time of the notification
            processing is error.
        :param event: dictionary of event that included in notification.
        """

        LOG.info("Send a notification. %s", event)

        # Send a notification.
        retry_count = 0
        while True:
            try:
                response = self.masakari_client.create_notification(
                    type=event['notification']['type'],
                    hostname=event['notification']['hostname'],
                    generated_time=event['notification']['generated_time'],
                    payload=event['notification']['payload'])

                LOG.info("Response: %s", response)
                break

            except Exception as e:
                if isinstance(e, exceptions.HttpException):
                    if e.status_code in [400, 409]:
                        LOG.info(e)
                        break

                if retry_count < api_retry_max:
                    LOG.warning("Retry sending a notification. (%s)", e)
                    retry_count = retry_count + 1
                    eventlet.greenthread.sleep(api_retry_interval)
                else:
                    LOG.exception("Exception caught: %s", e)
                    self._masakari_client = None
                    break
