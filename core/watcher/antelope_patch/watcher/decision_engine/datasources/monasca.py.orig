# -*- encoding: utf-8 -*-
# Copyright (c) 2016 b<>com
#
# Authors: Vincent FRANCOISE <vincent.francoise@b-com.com>
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

import datetime

from monascaclient import exc

from watcher.common import clients
from watcher.decision_engine.datasources import base


class MonascaHelper(base.DataSourceBase):

    NAME = 'monasca'
    METRIC_MAP = dict(host_cpu_usage='cpu.percent',
                      host_ram_usage=None,
                      host_outlet_temp=None,
                      host_inlet_temp=None,
                      host_airflow=None,
                      host_power=None,
                      instance_cpu_usage='vm.cpu.utilization_perc',
                      instance_ram_usage=None,
                      instance_ram_allocated=None,
                      instance_l3_cache_usage=None,
                      instance_root_disk_size=None,
                      )

    def __init__(self, osc=None):
        """:param osc: an OpenStackClients instance"""
        self.osc = osc if osc else clients.OpenStackClients()
        self.monasca = self.osc.monasca()

    def _format_time_params(self, start_time, end_time, period):
        """Format time-related params to the correct Monasca format

        :param start_time: Start datetime from which metrics will be used
        :param end_time: End datetime from which metrics will be used
        :param period: interval in seconds (int)
        :return: start ISO time, end ISO time, period
        """

        if not period:
            period = int(datetime.timedelta(hours=3).total_seconds())
        if not start_time:
            start_time = (
                datetime.datetime.utcnow() -
                datetime.timedelta(seconds=period))

        start_timestamp = None if not start_time else start_time.isoformat()
        end_timestamp = None if not end_time else end_time.isoformat()

        return start_timestamp, end_timestamp, period

    def query_retry_reset(self, exception_instance):
        if isinstance(exception_instance, exc.Unauthorized):
            self.osc.reset_clients()
            self.monasca = self.osc.monasca()

    def check_availability(self):
        result = self.query_retry(self.monasca.metrics.list)
        if result:
            return 'available'
        else:
            return 'not available'

    def list_metrics(self):
        # TODO(alexchadin): this method should be implemented in accordance to
        # monasca API.
        pass

    def statistic_aggregation(self, resource=None, resource_type=None,
                              meter_name=None, period=300, aggregate='mean',
                              granularity=300):
        stop_time = datetime.datetime.utcnow()
        start_time = stop_time - datetime.timedelta(seconds=(int(period)))

        meter = self._get_meter(meter_name)

        if aggregate == 'mean':
            aggregate = 'avg'

        raw_kwargs = dict(
            name=meter,
            start_time=start_time.isoformat(),
            end_time=stop_time.isoformat(),
            dimensions={'hostname': resource.uuid},
            period=period,
            statistics=aggregate,
            group_by='*',
        )

        kwargs = {k: v for k, v in raw_kwargs.items() if k and v}

        statistics = self.query_retry(
            f=self.monasca.metrics.list_statistics, **kwargs)

        cpu_usage = None
        for stat in statistics:
            avg_col_idx = stat['columns'].index(aggregate)
            values = [r[avg_col_idx] for r in stat['statistics']]
            value = float(sum(values)) / len(values)
            cpu_usage = value

        return cpu_usage

    def statistic_series(self, resource=None, resource_type=None,
                         meter_name=None, start_time=None, end_time=None,
                         granularity=300):

        meter = self._get_meter(meter_name)

        raw_kwargs = dict(
            name=meter,
            start_time=start_time.isoformat(),
            end_time=end_time.isoformat(),
            dimensions={'hostname': resource.uuid},
            statistics='avg',
            group_by='*',
        )

        kwargs = {k: v for k, v in raw_kwargs.items() if k and v}

        statistics = self.query_retry(
            f=self.monasca.metrics.list_statistics, **kwargs)

        result = {}
        for stat in statistics:
            v_index = stat['columns'].index('avg')
            t_index = stat['columns'].index('timestamp')
            result.update({r[t_index]: r[v_index] for r in stat['statistics']})

        return result

    def get_host_cpu_usage(self, resource, period,
                           aggregate, granularity=None):
        return self.statistic_aggregation(
            resource, 'compute_node', 'host_cpu_usage', period, aggregate,
            granularity)

    def get_host_ram_usage(self, resource, period,
                           aggregate, granularity=None):
        raise NotImplementedError

    def get_host_outlet_temp(self, resource, period,
                             aggregate, granularity=None):
        raise NotImplementedError

    def get_host_inlet_temp(self, resource, period,
                            aggregate, granularity=None):
        raise NotImplementedError

    def get_host_airflow(self, resource, period,
                         aggregate, granularity=None):
        raise NotImplementedError

    def get_host_power(self, resource, period,
                       aggregate, granularity=None):
        raise NotImplementedError

    def get_instance_cpu_usage(self, resource, period,
                               aggregate, granularity=None):

        return self.statistic_aggregation(
            resource, 'instance', 'instance_cpu_usage', period, aggregate,
            granularity)

    def get_instance_ram_usage(self, resource, period,
                               aggregate, granularity=None):
        raise NotImplementedError

    def get_instance_ram_allocated(self, resource, period,
                                   aggregate, granularity=None):
        raise NotImplementedError

    def get_instance_l3_cache_usage(self, resource, period,
                                    aggregate, granularity=None):
        raise NotImplementedError

    def get_instance_root_disk_size(self, resource, period,
                                    aggregate, granularity=None):
        raise NotImplementedError
