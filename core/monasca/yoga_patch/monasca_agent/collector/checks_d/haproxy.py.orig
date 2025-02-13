# (C) Copyright 2015,2016 Hewlett Packard Enterprise Development Company LP
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

from collections import defaultdict
import urllib


from monasca_agent.collector.checks import AgentCheck
from monasca_agent.common.util import headers


STATS_URL = "/;csv;norefresh"
EVENT_TYPE = SOURCE_TYPE_NAME = 'haproxy'


class Services(object):
    BACKEND = 'BACKEND'
    FRONTEND = 'FRONTEND'
    ALL = (BACKEND, FRONTEND)


class HAProxy(AgentCheck):

    def __init__(self, name, init_config, agent_config):
        AgentCheck.__init__(self, name, init_config, agent_config)

        # Host status needs to persist across all checks
        self.host_status = defaultdict(lambda: defaultdict(lambda: None))

    METRICS = {
        "qcur": ("gauge", "queue.current"),
        "scur": ("gauge", "session.current"),
        "slim": ("gauge", "session.limit"),
        "spct": ("gauge", "session.pct"),    # Calculated as: (scur/slim)*100
        "stot": ("rate", "session.rate"),
        "bin": ("rate", "bytes.in_rate"),
        "bout": ("rate", "bytes.out_rate"),
        "dreq": ("rate", "denied.req_rate"),
        "dresp": ("rate", "denied.resp_rate"),
        "ereq": ("rate", "errors.req_rate"),
        "econ": ("rate", "errors.con_rate"),
        "eresp": ("rate", "errors.resp_rate"),
        "wretr": ("rate", "warnings.retr_rate"),
        "wredis": ("rate", "warnings.redis_rate"),
        "req_rate": ("gauge", "requests.rate"),
        "hrsp_1xx": ("rate", "response.1xx"),
        "hrsp_2xx": ("rate", "response.2xx"),
        "hrsp_3xx": ("rate", "response.3xx"),
        "hrsp_4xx": ("rate", "response.4xx"),
        "hrsp_5xx": ("rate", "response.5xx"),
        "hrsp_other": ("rate", "response.other"),
    }

    def check(self, instance):
        self.dimensions = self._set_dimensions({'service': 'haproxy'}, instance)
        url = instance.get('url')
        username = instance.get('username')
        password = instance.get('password')
        collect_service_stats_only = instance.get('collect_service_stats_only', True)
        collect_aggregates_only = instance.get('collect_aggregates_only', True)
        collect_status_metrics = instance.get('collect_status_metrics', False)

        self.log.debug('Processing HAProxy data for %s' % url)

        data = self._fetch_data(url, username, password)

        self._process_data(data, collect_service_stats_only, collect_aggregates_only,
                           url=url, collect_status_metrics=collect_status_metrics)

    def _fetch_data(self, url, username, password):
        """Hit a given URL and return the parsed json.

        """
        # Try to fetch data from the stats URL

        passman = urllib.request.HTTPPasswordMgrWithDefaultRealm()
        passman.add_password(None, url, username, password)
        authhandler = urllib.request.HTTPBasicAuthHandler(passman)
        opener = urllib.request.build_opener(authhandler)
        urllib.request.install_opener(opener)
        url = "%s%s" % (url, STATS_URL)

        self.log.debug("HAProxy Fetching haproxy search data from: %s" % url)

        req = urllib.request.Request(url, None, headers(self.agent_config))
        request = urllib.request.urlopen(req)
        response = request.read()
        # Split the data by line
        return response.split('\n')

    def _process_data(self, data, collect_service_stats_only, collect_aggregates_only,
                      url=None, collect_status_metrics=False):
        """Main data-processing loop. For each piece of useful data, we'll

        save a metric.
        """

        # Split the first line into an index of fields
        # The line looks like:
        # "# pxname,svname,qcur,qmax,scur,smax,slim,stot,bin,bout,dreq,dresp,ereq,econ,eresp,wretr,
        # wredis,status,weight,act,bck,chkfail,chkdown,lastchg,downtime,qlimit,pid,iid,sid,throttle
        # ,lbtot,tracked,type,rate,rate_lim,rate_max,"
        fields = [f.strip() for f in data[0][2:].split(',') if f]

        hosts_statuses = defaultdict(int)

        # Holds a list of dictionaries describing each system
        data_list = []

        for line in data[1:]:  # Skip the first line
            if not line.strip():
                continue
            data_dict = {}
            values = line.split(',')

            # Store each line's values in a dictionary
            for i, val in enumerate(values):
                if val:
                    try:
                        # Try converting to a long, if failure, just leave it
                        val = float(val)
                    except Exception:  # nosec
                        pass
                    data_dict[fields[i]] = val

            if collect_service_stats_only and data_dict['pxname'] != 'stats':
                continue

            # The percentage of used sessions based on 'scur' and 'slim'
            if 'slim' in data_dict and 'scur' in data_dict:
                try:
                    data_dict['spct'] = (data_dict['scur'] / data_dict['slim']) * 100
                except (TypeError, ZeroDivisionError):
                    pass

            service = data_dict['svname']

            if collect_status_metrics and 'status' in data_dict and 'pxname' in data_dict:
                hosts_statuses[(data_dict['pxname'], data_dict['status'])] += 1

            if data_dict['svname'] in Services.ALL:
                data_list.append(data_dict)

                # Send the list of data to the metric callbacks
                self._process_metrics(data_list, service, url)

                # Clear out the list for the next service
                data_list = []
            elif not collect_aggregates_only:
                data_list.append(data_dict)

        if collect_status_metrics:
            self._process_status_metric(hosts_statuses)

        return data

    def _process_status_metric(self, hosts_statuses):
        agg_statuses = defaultdict(lambda: {'available': 0, 'unavailable': 0})
        status_dimensions = self.dimensions.copy()
        for (service, status), count in hosts_statuses.items():
            status = status.lower()

            status_dimensions.update({'status': status, 'component': service})
            self.gauge("haproxy.count_per_status", count, dimensions=status_dimensions)

            if 'up' in status:
                agg_statuses[service]['available'] += count
            if 'down' in status or 'maint' in status or 'nolb' in status:
                agg_statuses[service]['unavailable'] += count

        for service in agg_statuses:
            for status, count in agg_statuses[service].items():
                status_dimensions.update({'status': status, 'component': service})
                self.gauge("haproxy.count_per_status", count, dimensions=status_dimensions)

    def _process_metrics(self, data_list, service, url):
        for data in data_list:
            """Each element of data_list is a dictionary related to one host

            (one line) extracted from the csv. All of these elements should
            have the same value for 'pxname' key
            It should look like:
            data_list = [
                {'svname':'i-4562165', 'pxname':'dogweb', 'scur':'42', ...},
                {'svname':'i-2854985', 'pxname':'dogweb', 'scur':'1337', ...},
                ...
            ]
            """
            metric_dimensions = self.dimensions.copy()
            hostname = data['svname']
            service_name = data['pxname']

            metric_dimensions.update({'type': service,
                                      'instance_url': url,
                                      'component': service_name})
            if service == Services.BACKEND:
                metric_dimensions.update({'backend': hostname})

            for key, value in data.items():
                if HAProxy.METRICS.get(key):
                    suffix = HAProxy.METRICS[key][1]
                    name = "haproxy.%s.%s" % (service.lower(), suffix)
                    if HAProxy.METRICS[key][0] == 'rate':
                        self.rate(name, value, dimensions=metric_dimensions)
                    else:
                        self.gauge(name, value, dimensions=metric_dimensions)
