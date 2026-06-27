# Copyright (c) 2017 StackHPC Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

import logging
import os

import monasca_agent.collector.checks as checks

log = logging.getLogger(__name__)

# According to https://community.mellanox.com/docs/DOC-2572 these fields
# are divided by the number of lanes, so we need to multiply them by the lane
# count to get a number valid for the link as a whole.
_FIELDS_TO_MULTIPLY_BY_LANE_COUNT = {
    'port_rcv_data',
    'port_xmit_data'
}

_METRIC_NAME_PREFIX = "ibnet"
_IB_DEVICE_PATH = "/sys/class/infiniband/"
_IB_COUNTER_PATH = "ports/1/counters/"


class IBNetwork(checks.AgentCheck):
    def __init__(self, name, init_config, agent_config):
        super(IBNetwork, self).__init__(name, init_config, agent_config)

    @staticmethod
    def _get_lane_count():
        # It is possible that we could get the number of lanes from the driver,
        # for example:
        #
        # # cat /sys/class/infiniband/mlx5_0/ports/1/rate
        # 100 Gb/sec (4X EDR)
        #
        # However, according to the following PR this isn't expected to change:
        # https://github.com/prometheus/node_exporter/pull/579 so hard code it
        # for now.
        return 4

    def _normalise_counter(self, field, counter):
        if field in _FIELDS_TO_MULTIPLY_BY_LANE_COUNT:
            counter *= self._get_lane_count()
        return counter

    def _read_counter(self, device, field):
        counter_path = os.path.join(
            _IB_DEVICE_PATH, device, _IB_COUNTER_PATH, field)
        with open(counter_path) as f:
            counter = f.read()
        counter = int(counter.rstrip())
        counter = self._normalise_counter(field, counter)
        return counter

    @staticmethod
    def _get_devices():
        return os.listdir(_IB_DEVICE_PATH)

    @staticmethod
    def _get_fields(device):
        try:
            return os.listdir(os.path.join(
                _IB_DEVICE_PATH, device, _IB_COUNTER_PATH))
        except OSError:
            return []

    def check(self, instance):
        dimensions = self._set_dimensions(None, instance)

        for device in self._get_devices():
            for field in self._get_fields(device):
                counter = self._read_counter(device, field)
                metric_name = '{0}.{1}'.format(_METRIC_NAME_PREFIX, field)
                self.rate(metric_name,
                          counter,
                          device_name=device,
                          dimensions=dimensions)
            log.debug('Collected network interface status for device {0}'.
                      format(device))
