# Copyright 2024 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
#
from observabilityclient import prometheus_client
from oslo_config import cfg
from oslo_log import log
import re
from watcher._i18n import _
from watcher.common import exception
from watcher.decision_engine.datasources import base

CONF = cfg.CONF
LOG = log.getLogger(__name__)


class PrometheusHelper(base.DataSourceBase):
    """PrometheusHelper class for retrieving metrics from Prometheus server

    This class implements the DataSourceBase to allow Watcher to query
    Prometheus as a data source for metrics.
    """

    NAME = 'prometheus'
    METRIC_MAP = dict(host_cpu_usage='node_cpu_seconds_total',
                      host_ram_usage='node_memory_MemAvailable_bytes',
                      host_outlet_temp=None,
                      host_inlet_temp=None,
                      host_airflow=None,
                      host_power=None,
                      instance_cpu_usage='ceilometer_cpu',
                      instance_ram_usage='ceilometer_memory_usage',
                      instance_ram_allocated='instance.memory',
                      instance_l3_cache_usage=None,
                      instance_root_disk_size='instance.disk',
                      )
    AGGREGATES_MAP = dict(mean='avg', max='max', min='min', count='avg')

    def __init__(self):
        """Initialise the PrometheusHelper

        The prometheus helper uses the PrometheusAPIClient provided by
        python-observabilityclient.
        The prometheus_fqdn_labels contains a list the values contained in
        the fqdn_label in the Prometheus instance. When making queries to
        Prometheus we use the fqdn_label to specify the node for which
         metrics are to be retrieved.
        host, port and fqdn_label come from watcher_client
        config. The prometheus_fqdn_label allows override of the required label
        in Prometheus scrape configs that specifies each target's fqdn.
        """
        self.prometheus = self._setup_prometheus_client()
        self.prometheus_fqdn_label = (
            CONF.prometheus_client.fqdn_label
        )
        self.prometheus_fqdn_labels = (
            self._build_prometheus_fqdn_labels()
        )
        self.prometheus_host_instance_map = (
            self._build_prometheus_host_instance_map()
        )

    def _setup_prometheus_client(self):
        """Initialise the prometheus client with config options

        Use the prometheus_client options in watcher.conf to setup
        the PrometheusAPIClient client object and return it.
        :raises watcher.common.exception.MissingParameter if
                prometheus host or port is not set in the watcher.conf
                under the [prometheus_client] section.
        :raises watcher.common.exception.InvalidParameter if
                the prometheus host or port have invalid format.
        """
        def _validate_host_port(host, port):
            if len(host) > 255:
                return (False, "hostname is too long: '%s'" % host)
            if host[-1] == '.':
                host = host[:-1]
            legal_hostname = re.compile(
                "(?!-)[a-z0-9-]{1,63}(?<!-)$", re.IGNORECASE)
            if not all(legal_hostname.match(host_part)
                       for host_part in host.split(".")):
                return (False, "hostname '%s' failed regex match " % host)
            try:
                assert bool(1 <= int(port) <= 65535)
            except (AssertionError, ValueError):
                return (False, "missing or invalid port number '%s' "
                        % port)
            return (True, "all good")

        _host = CONF.prometheus_client.host
        _port = CONF.prometheus_client.port
        if (not _host or not _port):
            raise exception.MissingParameter(
                message=(_(
                    "prometheus host and port must be set in watcher.conf "
                    "under the [prometheus_client] section. Can't initialise "
                    "the datasource without valid host and port."))
            )
        validated, reason = _validate_host_port(_host, _port)
        if (not validated):
            raise exception.InvalidParameter(
                message=(_(
                    "A valid prometheus host and port are required. The #"
                    "values found in watcher.conf are '%(host)s' '%(port)s'. "
                    "This fails validation for the following reason: "
                    "%(reason)s.")
                    % {'host': _host, 'port': _port, 'reason': reason})
            )
        the_client = prometheus_client.PrometheusAPIClient(
            "%s:%s" % (_host, _port))

        # check if tls options or basic_auth options are set and use them
        prometheus_user = CONF.prometheus_client.username
        prometheus_pass = CONF.prometheus_client.password
        prometheus_ca_cert = CONF.prometheus_client.cafile
        prometheus_client_cert = CONF.prometheus_client.certfile
        prometheus_client_key = CONF.prometheus_client.keyfile
        if (prometheus_ca_cert):
            the_client.set_ca_cert(prometheus_ca_cert)
            if (prometheus_client_cert and prometheus_client_key):
                the_client.set_client_cert(
                    prometheus_client_cert, prometheus_client_key)
        if (prometheus_user and prometheus_pass):
            the_client.set_basic_auth(prometheus_user, prometheus_pass)

        return the_client

    def _build_prometheus_fqdn_labels(self):
        """Build the list of fqdn_label values to be used in host queries

        Watcher knows nodes by their hostname. In Prometheus however the
        scrape targets (also known as 'instances') are specified by I.P.
        (or hostname) and port number and fqdn is stored in a custom 'fqdn'
        label added to Prometheus scrape_configs. Operators can use a
        different custom label instead by setting the prometheus_fqdn_label
        config option under the prometheus_client section of watcher config.
        The built prometheus_fqdn_labels is created with the full list
        of values of the prometheus_fqdn_label label in Prometheus. This will
        be used to create a map of hostname<-->fqdn and to identify if a target
        exist in prometheus for the compute nodes before sending the query.
        :return a set of values of the fqdn label. For example:
                {'foo.example.com', 'bar.example.com'}
                {'foo', 'bar'}
        """
        prometheus_targets = self.prometheus._get(
            "targets?state=active")['data']['activeTargets']
        # >>> prometheus_targets[0]['labels']
        # {'fqdn': 'marios-env-again.controlplane.domain',
        #  'instance': 'localhost:9100', 'job': 'node'}
        fqdn_instance_labels = set()
        for target in prometheus_targets:
            if target.get('labels', {}).get(self.prometheus_fqdn_label):
                fqdn_instance_labels.add(
                    target['labels'].get(self.prometheus_fqdn_label))

        if not fqdn_instance_labels:
            LOG.error(
                "Could not create fqdn labels list from Prometheus "
                "targets config. Prometheus returned the following: %s",
                prometheus_targets
            )
            return set()
        return fqdn_instance_labels

    def _build_prometheus_host_instance_map(self):
        """Build the hostname<-->instance_label mapping needed for queries

        The prometheus_fqdn_labels has the fully qualified domain name
        for hosts. This will create a duplicate map containing only the host
        name part. Depending on the watcher node.hostname either the
        fqdn_instance_labels or the host_instance_map will be used to resolve
        the correct prometheus fqdn_label for queries. In the event the
        fqdn_instance_labels elements are not valid fqdn (for example it has
        hostnames, not fqdn) the host_instance_map cannot be created and
        an empty dictionary is returned with a warning logged.
        :return a dict mapping hostname to instance label. For example:
                {'foo': 'foo.example.com', 'bar': 'bar.example.com'}
        """
        if not self.prometheus_fqdn_labels:
            LOG.error("Cannot build host_instance_map without "
                      "fqdn_instance_labels")
            return {}
        host_instance_map = {
            host: fqdn for (host, fqdn) in (
                (fqdn.split('.')[0], fqdn)
                for fqdn in self.prometheus_fqdn_labels
                if '.' in fqdn
            )
        }
        if not host_instance_map:
            LOG.warning("Creating empty host instance map. Are the keys "
                        "in prometheus_fqdn_labels valid fqdn?")
            return {}
        return host_instance_map

    def _resolve_prometheus_instance_label(self, node_name):
        """Resolve the prometheus instance label to use in queries

        Given the watcher node.hostname, resolve the prometheus instance
        label for use in queries, first trying the fqdn_instance_labels and
        then the host_instance_map (watcher.node_name can be fqdn or hostname).
        If the name is not resolved after the first attempt, rebuild the fqdn
        and host instance maps and try again. This allows for new hosts added
        after the initialisation of the fqdn_instance_labels.
        :param node_name: the watcher node.hostname
        :return String for the prometheus instance label and None if not found
        """
        def _query_maps(node):
            if node in self.prometheus_fqdn_labels:
                return node
            else:
                return self.prometheus_host_instance_map.get(node, None)

        instance_label = _query_maps(node_name)
        # refresh the fqdn and host instance maps and retry
        if not instance_label:
            self.prometheus_fqdn_labels = (
                self._build_prometheus_fqdn_labels()
            )
            self.prometheus_host_instance_map = (
                self._build_prometheus_host_instance_map()
            )
            instance_label = _query_maps(node_name)

        if not instance_label:
            LOG.error("Cannot query prometheus without instance label. "
                      "Could not resolve %s", node_name)
            return None
        return instance_label

    def _resolve_prometheus_aggregate(self, watcher_aggregate, meter):
        """Resolve the prometheus aggregate using self.AGGREGATES_MAP

        This uses the AGGREGATES_MAP to resolve the correct prometheus
        aggregate to use in queries, from the given watcher aggregate
        """
        if watcher_aggregate == 'count':
            LOG.warning('Prometheus data source does not currently support '
                        ' the count aggregate. Proceeding with mean (avg).')
        promql_aggregate = self.AGGREGATES_MAP.get(watcher_aggregate)
        if not promql_aggregate:
            raise exception.InvalidParameter(
                message=(_("Unknown Watcher aggregate %s. This does not "
                           "resolve to any valid prometheus query aggregate.")
                         % watcher_aggregate)
            )
        return promql_aggregate

    def _build_prometheus_query(self, aggregate, meter, instance_label,
                                period, resource=None):
        """Build and return the prometheus query string with the given args

        This function builds and returns the string query that will be sent
        to the Prometheus server /query endpoint. For host cpu usage we use:

        100 - (avg by (fqdn)(rate(node_cpu_seconds_total{mode='idle',
                                       fqdn='some_host'}[300s])) * 100)

        so using prometheus rate function over the specified period, we average
        per instance (all cpus) idle time and then 'everything else' is cpu
        usage time.

        For host memory usage we use:

        (node_memory_MemTotal_bytes{instance='the_host'} -
        avg_over_time(
            node_memory_MemAvailable_bytes{instance='the_host'}[300s]))
            / 1024

        So we take total and subtract available memory to determine
        how much is in use. We use the prometheus xxx_over_time functions
        avg/max/min depending on the aggregate with the specified time period.

        :param aggregate: one of the values of self.AGGREGATES_MAP
        :param meter: the name of the Prometheus meter to use
        :param instance_label: the Prometheus instance label (scrape target).
        :param period: the period in seconds for which to query
        :param resource: the resource object for which metrics are requested
        :return: a String containing the Prometheus query
        :raises watcher.common.exception.InvalidParameter if params are None
        :raises watcher.common.exception.InvalidParameter if meter is not
                known or currently supported (prometheus meter name).
        """
        query_args = None
        uuid_label_key = CONF.prometheus_client.instance_uuid_label
        if (meter is None or aggregate is None or instance_label is None or
                period is None):
            raise exception.InvalidParameter(
                message=(_(
                    "Cannot build prometheus query without args. "
                    "You provided: meter %(mtr)s, aggregate %(agg)s, "
                    "instance_label %(inst)s, period %(prd)s")
                    % {'mtr': meter, 'agg': aggregate,
                       'inst': instance_label, 'prd': period})
            )

        if meter == 'node_cpu_seconds_total':
            query_args = (
                "100 - (%(agg)s by (%(label)s)(rate(%(meter)s"
                "{mode='idle',%(label)s='%(label_value)s'}[%(period)ss])) "
                "* 100)"
                % {'label': self.prometheus_fqdn_label,
                   'label_value': instance_label, 'agg': aggregate,
                   'meter': meter, 'period': period}
            )
        elif meter == 'node_memory_MemAvailable_bytes':
            # Prometheus metric is in B and we need to return KB
            query_args = (
                "(node_memory_MemTotal_bytes{%(label)s='%(label_value)s'} "
                "- %(agg)s_over_time(%(meter)s{%(label)s='%(label_value)s'}"
                "[%(period)ss])) / 1024"
                % {'label': self.prometheus_fqdn_label,
                   'label_value': instance_label, 'agg': aggregate,
                   'meter': meter, 'period': period}
            )
        elif meter == 'ceilometer_memory_usage':
            query_args = (
                "%s_over_time(%s{%s='%s'}[%ss])" %
                (aggregate, meter, uuid_label_key, instance_label, period)
            )
        elif meter == 'ceilometer_cpu':
            # We are converting the total cumulative cpu time (ns) to cpu usage
            # percentage so we need to divide between the number of vcpus.
            # As this is a percentage metric, we set a max level of 100. It has
            # been observed in very high usage cases, prometheus reporting
            # values higher that 100 what can lead to unexpected behaviors.
            vcpus = resource.vcpus
            if not vcpus:
                LOG.warning(
                    "instance vcpu count not set for instance %s, assuming 1",
                    instance_label
                )
                vcpus = 1
            query_args = (
                "clamp_max((%(agg)s by (%(label)s)"
                "(rate(%(meter)s{%(label)s='%(label_value)s'}[%(period)ss]))"
                "/10e+8) *(100/%(vcpus)s), 100)"
                % {'label': uuid_label_key, 'label_value': instance_label,
                   'agg': aggregate, 'meter': meter, 'period': period,
                   'vcpus': vcpus}
            )
        else:
            raise exception.InvalidParameter(
                message=(_("Cannot process prometheus meter %s") % meter)
            )

        return query_args

    def check_availability(self):
        """check if Prometheus server is available for queries

         Performs HTTP get on the prometheus API /status/runtimeinfo endpoint.
         The prometheus_client will raise a PrometheuAPIClientError if the
         call is unsuccessful, which is caught here and a warning logged.
        """
        try:
            self.prometheus._get("status/runtimeinfo")
        except prometheus_client.PrometheusAPIClientError:
            LOG.warning(
                "check_availability raised PrometheusAPIClientError. "
                "Is Prometheus server down?"
            )
            return 'not available'
        return 'available'

    def list_metrics(self):
        """Fetch all prometheus metrics from api/v1/label/__name__/values

        The prometheus_client will raise a PrometheuAPIClientError if the
        call is unsuccessful, which is caught here and a warning logged.
        """
        try:
            response = self.prometheus._get("label/__name__/values")
        except prometheus_client.PrometheusAPIClientError:
            LOG.warning(
                "list_metrics raised PrometheusAPIClientError. Is Prometheus"
                "server down?"
            )
            return set()
        return set(response['data'])

    def statistic_aggregation(self, resource=None, resource_type=None,
                              meter_name=None, period=300, aggregate='mean',
                              granularity=300):

        meter = self._get_meter(meter_name)
        query_args = ''
        instance_label = ''

        # For instance resource type, the datasource expects the uuid of the
        # instance to be assigned to a label in the prometheus metrics, with a
        # specific key value.
        if resource_type == 'compute_node':
            instance_label = self._resolve_prometheus_instance_label(
                resource.hostname)
        elif resource_type == 'instance':
            instance_label = resource.uuid
            # For ram_allocated and root_disk size metrics there are no valid
            # values in the prometheus backend store. We rely in the values
            # provided in the vms inventory.
            if meter == 'instance.memory':
                return float(resource.memory)
            elif meter == 'instance.disk':
                return float(resource.disk)
        else:
            LOG.warning(
                "Prometheus data source does not currently support "
                "resource_type %s", resource_type
            )
            return None

        promql_aggregate = self._resolve_prometheus_aggregate(aggregate, meter)
        query_args = self._build_prometheus_query(
            promql_aggregate, meter, instance_label, period, resource
        )
        if not query_args:
            LOG.error("Cannot proceed without valid prometheus query")
            return None

        result = self.query_retry(
            self.prometheus.query, query_args,
            ignored_exc=prometheus_client.PrometheusAPIClientError,
        )

        return float(result[0].value) if result else None

    def statistic_series(self, resource=None, resource_type=None,
                         meter_name=None, start_time=None, end_time=None,
                         granularity=300):
        raise NotImplementedError(
            _('Prometheus helper currently does not support statistic_series. '
              'This can be considered for future enhancement.'))

    def _invert_max_min_aggregate(self, agg):
        """Invert max and min for node/host metric queries from node-exporter

            because we query for 'idle'/'unused' cpu and memory.
            For Watcher 'max cpu used' we query for prometheus 'min idle time'.
            For Watcher 'max memory used' we retrieve min 'unused'/'available'
            memory from Prometheus. This internal function is used exclusively
            by get_host_cpu_usage and get_host_ram_usage.
            :param agg: the metric collection aggregate
            :return: a String aggregate

        """
        if agg == 'max':
            return 'min'
        elif agg == 'min':
            return 'max'
        return agg

    def get_host_cpu_usage(self, resource, period=300,
                           aggregate="mean", granularity=None):
        """Query prometheus for node_cpu_seconds_total

        This calculates the host cpu usage and returns it as a percentage
        The calculation is made by using the cpu 'idle' time, per
        instance (so all CPUs are included). For example the query looks like
        (100 - (avg by (fqdn)(rate(node_cpu_seconds_total
            {mode='idle',fqdn='compute1.example.com'}[300s])) * 100))
        """
        aggregate = self._invert_max_min_aggregate(aggregate)
        cpu_usage = self.statistic_aggregation(
            resource, 'compute_node',
            'host_cpu_usage', period=period,
            granularity=granularity, aggregate=aggregate)
        return float(cpu_usage) if cpu_usage else None

    def get_host_ram_usage(self, resource, period=300,
                           aggregate="mean", granularity=None):
        aggregate = self._invert_max_min_aggregate(aggregate)
        ram_usage = self.statistic_aggregation(
            resource, 'compute_node',
            'host_ram_usage', period=period,
            granularity=granularity, aggregate=aggregate)
        return float(ram_usage) if ram_usage else None

    def get_instance_ram_usage(self, resource, period=300,
                               aggregate="mean", granularity=None):
        ram_usage = self.statistic_aggregation(
            resource, 'instance',
            'instance_ram_usage', period=period,
            granularity=granularity, aggregate=aggregate)
        return ram_usage

    def get_instance_cpu_usage(self, resource, period=300,
                               aggregate="mean", granularity=None):
        cpu_usage = self.statistic_aggregation(
            resource, 'instance',
            'instance_cpu_usage', period=period,
            granularity=granularity, aggregate=aggregate)
        return cpu_usage

    def get_instance_ram_allocated(self, resource, period=300,
                                   aggregate="mean", granularity=None):
        ram_allocated = self.statistic_aggregation(
            resource, 'instance',
            'instance_ram_allocated', period=period,
            granularity=granularity, aggregate=aggregate)
        return ram_allocated

    def get_instance_root_disk_size(self, resource, period=300,
                                    aggregate="mean", granularity=None):
        root_disk_size = self.statistic_aggregation(
            resource, 'instance',
            'instance_root_disk_size', period=period,
            granularity=granularity, aggregate=aggregate)
        return root_disk_size
