# (C) Copyright 2015-2016 Hewlett Packard Enterprise Development Company LP
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
import re
import subprocess

import monasca_agent.collector.checks as checks
from monasca_agent.common.psutil_wrapper import psutil


log = logging.getLogger(__name__)


class Cpu(checks.AgentCheck):

    def __init__(self, name, init_config, agent_config):
        super(Cpu, self).__init__(name, init_config, agent_config)
        process_fs_path_config = init_config.get('process_fs_path', None)
        if process_fs_path_config:
            psutil.PROCFS_PATH = process_fs_path_config
            self.log.debug('The path of the process filesystem set to %s', process_fs_path_config)
        else:
            self.log.debug('The process_fs_path not set. Use default path: /proc')
        # psutil.cpu_percent and psutil.cpu_times_percent are called in
        # __init__ because the first time these two functions are called with
        # interval = 0.0 or None, it will return a meaningless 0.0 value
        # which you are supposed to ignore.
        psutil.cpu_percent(interval=None, percpu=False)
        psutil.cpu_times_percent(interval=None, percpu=False)

    def check(self, instance):
        """Capture cpu stats
        """
        num_of_metrics = 0
        dimensions = self._set_dimensions(None, instance)

        if instance is not None:
            send_rollup_stats = instance.get("send_rollup_stats", False)
        else:
            send_rollup_stats = False

        cpu_stats = psutil.cpu_times_percent(interval=None, percpu=False)
        cpu_times = psutil.cpu_times(percpu=False)
        cpu_perc = psutil.cpu_percent(interval=None, percpu=False)

        data = {'cpu.user_perc': cpu_stats.user + cpu_stats.nice,
                'cpu.system_perc': cpu_stats.system + cpu_stats.irq + cpu_stats.softirq,
                'cpu.wait_perc': cpu_stats.iowait,
                'cpu.idle_perc': cpu_stats.idle,
                'cpu.stolen_perc': cpu_stats.steal,
                'cpu.percent': cpu_perc,
                'cpu.idle_time': cpu_times.idle,
                'cpu.wait_time': cpu_times.iowait,
                'cpu.user_time': cpu_times.user + cpu_times.nice,
                'cpu.system_time': cpu_times.system + cpu_times.irq + cpu_times.softirq}

        # Call lscpu command to get cpu frequency
        self._add_cpu_freq(data)

        for key, value in data.items():
            if data[key] is None or instance.get('cpu_idle_only') and 'idle_perc' not in key:
                continue
            self.gauge(key, value, dimensions)
            num_of_metrics += 1

        if send_rollup_stats:
            self.gauge('cpu.total_logical_cores', psutil.cpu_count(logical=True), dimensions)
            num_of_metrics += 1
        log.debug('Collected {0} cpu metrics'.format(num_of_metrics))

    def _add_cpu_freq(self, data):
        try:
            lscpu_command = subprocess.Popen(
                'lscpu', stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            lscpu_output = lscpu_command.communicate()[0].decode(
                encoding='UTF-8')
            cpu_freq_output = re.search(r"(CPU MHz:.*?(\d+\.\d+)\n)", lscpu_output)
            cpu_freq = float(cpu_freq_output.group(2))
            data['cpu.frequency_mhz'] = cpu_freq
        except Exception:
            log.exception('Cannot extract CPU MHz information using lscpu')
