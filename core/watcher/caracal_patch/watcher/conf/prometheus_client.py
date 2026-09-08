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

from oslo_config import cfg

prometheus_client = cfg.OptGroup(name='prometheus_client',
                                 title='Configuration Options for Prometheus',
                                 help="See https://docs.openstack.org/watcher/"
                                      "latest/datasources/prometheus.html for "
                                      "details on how these options are used.")

PROMETHEUS_CLIENT_OPTS = [
    cfg.StrOpt('host',
               help="The hostname or IP address for the prometheus server."),
    cfg.StrOpt('port',
               help="The port number used by the prometheus server."),
    cfg.StrOpt('fqdn_label',
               default="fqdn",
               help="The label that Prometheus uses to store the fqdn of "
                    "exporters. Defaults to 'fqdn'."),
    cfg.StrOpt('instance_uuid_label',
               default="resource",
               help="The label that Prometheus uses to store the uuid of "
                    "OpenStack instances. Defaults to 'resource'."),
    cfg.StrOpt('username',
               help="The basic_auth username to use to authenticate with the "
                    "Prometheus server."),
    cfg.StrOpt('password',
               secret=True,
               help="The basic_auth password to use to authenticate with the "
                    "Prometheus server."),
    cfg.StrOpt('cafile',
               help="Path to the CA certificate for establishing a TLS "
                    "connection with the Prometheus server."),
    cfg.StrOpt('certfile',
               help="Path to the client certificate for establishing a TLS "
                    "connection with the Prometheus server."),
    cfg.StrOpt('keyfile',
               help="Path to the client key for establishing a TLS "
                    "connection with the Prometheus server."),
]


def register_opts(conf):
    conf.register_group(prometheus_client)
    conf.register_opts(PROMETHEUS_CLIENT_OPTS, group=prometheus_client)


def list_opts():
    return [(prometheus_client, PROMETHEUS_CLIENT_OPTS)]
