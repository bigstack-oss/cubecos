# (C) Copyright 2015 Hewlett Packard Enterprise Development Company LP
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

# stdlib

import logging
import socket
import urllib

# project
import monasca_agent.collector.checks as checks
import monasca_agent.collector.checks.services_checks as services_checks
import monasca_agent.collector.checks.utils as utils
import monasca_agent.common.util as util

log = logging.getLogger(__name__)


class Apache(checks.AgentCheck):
    """Tracks basic connection/requests/workers metrics

    See http://httpd.apache.org/docs/2.2/mod/mod_status.html for more details
    """

    GAUGES = {'IdleWorkers': 'apache.performance.idle_worker_count',
              'BusyWorkers': 'apache.performance.busy_worker_count',
              'CPULoad': 'apache.performance.cpu_load_perc',
              'Total kBytes': 'apache.net.total_kbytes',
              'Total Accesses': 'apache.net.hits',
              }
    RATES = {'Total kBytes': 'apache.net.kbytes_sec',
             'Total Accesses': 'apache.net.requests_sec'
             }

    def __init__(self, name, init_config, agent_config, instances=None):
        super(Apache, self).__init__(name, init_config, agent_config, instances)
        self.url = None

    def check(self, instance):
        self.url = instance.get('apache_status_url', None)
        if not self.url:
            raise Exception("Missing 'apache_status_url' in Apache config")

        req = urllib.request.Request(self.url, None, util.headers(self.agent_config))
        apache_user = instance.get('apache_user', None)
        apache_password = instance.get('apache_password', None)
        if apache_user and apache_password:
            utils.add_basic_auth(req, apache_user, apache_password)
        else:
            log.debug("Not using authentication for Apache Web Server")

        # Submit a service check for status page availability.
        parsed_url = urllib.parse.urlparse(self.url)
        apache_host = parsed_url.hostname
        apache_port = str(parsed_url.port or 80)
        service_check_name = 'apache.status'

        # Add additional dimensions
        if apache_host == 'localhost':
            # Localhost is not very useful, so get the actual hostname
            apache_host = socket.gethostname()

        dimensions = self._set_dimensions({'apache_host': apache_host,
                                           'apache_port': apache_port,
                                           'service': 'apache',
                                           'component': 'apache'},
                                          instance)

        try:
            request = urllib.request.urlopen(req)
        except Exception as e:
            self.log.info(
                "%s is DOWN, error: %s. Connection failed." % (service_check_name, str(e)))
            self.gauge(service_check_name, 1, dimensions=dimensions)
            return services_checks.Status.DOWN, "%s is DOWN, error: %s. Connection failed." % (
                service_check_name, str(e))
        else:
            self.log.debug("%s is UP" % service_check_name)
            self.gauge(service_check_name, 0, dimensions=dimensions)

        response = request.read()
        metric_count = 0

        # Loop through and extract the numerical values
        for line in response.split('\n'):
            values = line.split(': ')
            if len(values) == 2:  # match
                metric, value = values
                try:
                    value = float(value)
                except ValueError:
                    continue

                # Send metric as a gauge, if applicable
                if metric in self.GAUGES:
                    metric_count += 1
                    metric_name = self.GAUGES[metric]
                    log.debug('Collecting gauge data for: {0}'.format(metric_name))
                    self.gauge(metric_name, value, dimensions=dimensions)

                # Send metric as a rate, if applicable
                if metric in self.RATES:
                    metric_count += 1
                    metric_name = self.RATES[metric]
                    log.debug('Collecting rate data for: {0}'.format(metric_name))
                    self.rate(metric_name, value, dimensions=dimensions)

        if metric_count == 0:
            if self.url[-5:] != '?auto':
                self.url = '%s?auto' % self.url
                self.log.warn("Assuming url was not correct. Trying to add ?auto suffix to the url")
                self.check(instance)
            else:
                return services_checks.Status.DOWN,
                "{} is DOWN, error: No metrics available.".format(
                    service_check_name)
        else:
            log.debug("Collected {0} metrics for {1} Apache Web Server".format(apache_host,
                                                                               metric_count))
