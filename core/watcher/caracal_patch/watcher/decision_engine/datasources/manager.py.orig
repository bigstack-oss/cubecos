# -*- encoding: utf-8 -*-
# Copyright 2017 NEC Corporation
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

import os
import yaml

from collections import OrderedDict
from oslo_config import cfg
from oslo_log import log

from watcher.common import exception
from watcher.decision_engine.datasources import ceilometer as ceil
from watcher.decision_engine.datasources import gnocchi as gnoc
from watcher.decision_engine.datasources import grafana as graf
from watcher.decision_engine.datasources import monasca as mon

LOG = log.getLogger(__name__)


class DataSourceManager(object):

    metric_map = OrderedDict([
        (gnoc.GnocchiHelper.NAME, gnoc.GnocchiHelper.METRIC_MAP),
        (ceil.CeilometerHelper.NAME, ceil.CeilometerHelper.METRIC_MAP),
        (mon.MonascaHelper.NAME, mon.MonascaHelper.METRIC_MAP),
        (graf.GrafanaHelper.NAME, graf.GrafanaHelper.METRIC_MAP),
    ])
    """Dictionary with all possible datasources, dictionary order is the default
    order for attempting to use datasources
    """

    def __init__(self, config=None, osc=None):
        self.osc = osc
        self.config = config
        self._ceilometer = None
        self._monasca = None
        self._gnocchi = None
        self._grafana = None

        # Dynamically update grafana metric map, only available at runtime
        # The metric map can still be overridden by a yaml config file
        self.metric_map[graf.GrafanaHelper.NAME] = self.grafana.METRIC_MAP

        metric_map_path = cfg.CONF.watcher_decision_engine.metric_map_path
        metrics_from_file = self.load_metric_map(metric_map_path)
        for ds, mp in self.metric_map.items():
            try:
                self.metric_map[ds].update(metrics_from_file.get(ds, {}))
            except KeyError:
                msgargs = (ds, self.metric_map.keys())
                LOG.warning('Invalid Datasource: %s. Allowed: %s ', *msgargs)

        self.datasources = self.config.datasources

    @property
    def ceilometer(self):
        if self._ceilometer is None:
            self.ceilometer = ceil.CeilometerHelper(osc=self.osc)
        return self._ceilometer

    @ceilometer.setter
    def ceilometer(self, ceilometer):
        self._ceilometer = ceilometer

    @property
    def monasca(self):
        if self._monasca is None:
            self._monasca = mon.MonascaHelper(osc=self.osc)
        return self._monasca

    @monasca.setter
    def monasca(self, monasca):
        self._monasca = monasca

    @property
    def gnocchi(self):
        if self._gnocchi is None:
            self._gnocchi = gnoc.GnocchiHelper(osc=self.osc)
        return self._gnocchi

    @gnocchi.setter
    def gnocchi(self, gnocchi):
        self._gnocchi = gnocchi

    @property
    def grafana(self):
        if self._grafana is None:
            self._grafana = graf.GrafanaHelper(osc=self.osc)
        return self._grafana

    @grafana.setter
    def grafana(self, grafana):
        self._grafana = grafana

    def get_backend(self, metrics):
        """Determine the datasource to use from the configuration

        Iterates over the configured datasources in order to find the first
        which can support all specified metrics. Upon a missing metric the next
        datasource is attempted.
        """

        if not self.datasources or len(self.datasources) == 0:
            raise exception.NoDatasourceAvailable

        if not metrics or len(metrics) == 0:
            LOG.critical("Can not retrieve datasource without specifying "
                         "list of required metrics.")
            raise exception.InvalidParameter(parameter='metrics',
                                             parameter_type='none empty list')

        for datasource in self.datasources:
            no_metric = False
            for metric in metrics:
                if (metric not in self.metric_map[datasource] or
                        self.metric_map[datasource].get(metric) is None):
                    no_metric = True
                    LOG.warning("Datasource: {0} could not be used due to "
                                "metric: {1}".format(datasource, metric))
                    break
            if not no_metric:
                # Try to use a specific datasource but attempt additional
                # datasources upon exceptions (if config has more datasources)
                try:
                    ds = getattr(self, datasource)
                    ds.METRIC_MAP.update(self.metric_map[ds.NAME])
                    return ds
                except Exception:
                    pass
        raise exception.MetricNotAvailable(metric=metric)

    def load_metric_map(self, file_path):
        """Load metrics from the metric_map_path"""
        if file_path and os.path.exists(file_path):
            with open(file_path, 'r') as f:
                try:
                    ret = yaml.safe_load(f.read())
                    # return {} if the file is empty
                    return ret if ret else {}
                except yaml.YAMLError as e:
                    LOG.warning('Could not load %s: %s', file_path, e)
                return {}
        else:
            return {}
