# -*- encoding: utf-8 -*-
# Copyright (c) 2016 b<>com
# Copyright (c) 2016 Intel Corp
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

from oslo_config import cfg

from watcher.conf import api
from watcher.conf import applier
from watcher.conf import ceilometer_client
from watcher.conf import cinder_client
from watcher.conf import clients_auth
from watcher.conf import collector
from watcher.conf import datasources
from watcher.conf import db
from watcher.conf import decision_engine
from watcher.conf import exception
from watcher.conf import glance_client
from watcher.conf import gnocchi_client
from watcher.conf import grafana_client
from watcher.conf import grafana_translators
from watcher.conf import ironic_client
from watcher.conf import keystone_client
from watcher.conf import maas_client
from watcher.conf import monasca_client
from watcher.conf import neutron_client
from watcher.conf import nova_client
from watcher.conf import paths
from watcher.conf import placement_client
from watcher.conf import planner
from watcher.conf import service

CONF = cfg.CONF

service.register_opts(CONF)
api.register_opts(CONF)
paths.register_opts(CONF)
exception.register_opts(CONF)
datasources.register_opts(CONF)
db.register_opts(CONF)
planner.register_opts(CONF)
applier.register_opts(CONF)
decision_engine.register_opts(CONF)
maas_client.register_opts(CONF)
monasca_client.register_opts(CONF)
nova_client.register_opts(CONF)
glance_client.register_opts(CONF)
gnocchi_client.register_opts(CONF)
keystone_client.register_opts(CONF)
grafana_client.register_opts(CONF)
grafana_translators.register_opts(CONF)
cinder_client.register_opts(CONF)
ceilometer_client.register_opts(CONF)
neutron_client.register_opts(CONF)
clients_auth.register_opts(CONF)
ironic_client.register_opts(CONF)
collector.register_opts(CONF)
placement_client.register_opts(CONF)
