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

from oslo_config import cfg

from cinderclient import client as ciclient
from glanceclient import client as glclient
from gnocchiclient import client as gnclient
from ironicclient import client as irclient
from keystoneauth1 import adapter as ka_adapter
from keystoneauth1 import loading as ka_loading
from keystoneclient import client as keyclient
from monascaclient import client as monclient
from neutronclient.neutron import client as netclient
from novaclient import api_versions as nova_api_versions
from novaclient import client as nvclient

from watcher.common import exception

try:
    from ceilometerclient import client as ceclient
    HAS_CEILCLIENT = True
except ImportError:
    HAS_CEILCLIENT = False

CONF = cfg.CONF

_CLIENTS_AUTH_GROUP = 'watcher_clients_auth'

# NOTE(mriedem): This is the minimum required version of the nova API for
# watcher features to work. If new features are added which require new
# versions, they should perform version discovery and be backward compatible
# for at least one release before raising the minimum required version.
MIN_NOVA_API_VERSION = '2.56'


def check_min_nova_api_version(config_version):
    """Validates the minimum required nova API version.

    :param config_version: The configured [nova_client]/api_version value
    :raises: ValueError if the configured version is less than the required
        minimum
    """
    min_required = nova_api_versions.APIVersion(MIN_NOVA_API_VERSION)
    if nova_api_versions.APIVersion(config_version) < min_required:
        raise ValueError('Invalid nova_client.api_version %s. %s or '
                         'greater is required.' % (config_version,
                                                   MIN_NOVA_API_VERSION))


class OpenStackClients(object):
    """Convenience class to create and cache client instances."""

    def __init__(self):
        self.reset_clients()

    def reset_clients(self):
        self._session = None
        self._keystone = None
        self._nova = None
        self._glance = None
        self._gnocchi = None
        self._cinder = None
        self._ceilometer = None
        self._monasca = None
        self._neutron = None
        self._ironic = None
        self._placement = None

    def _get_keystone_session(self):
        auth = ka_loading.load_auth_from_conf_options(CONF,
                                                      _CLIENTS_AUTH_GROUP)
        sess = ka_loading.load_session_from_conf_options(CONF,
                                                         _CLIENTS_AUTH_GROUP,
                                                         auth=auth)
        return sess

    @property
    def auth_url(self):
        return self.keystone().auth_url

    @property
    def session(self):
        if not self._session:
            self._session = self._get_keystone_session()
        return self._session

    def _get_client_option(self, client, option):
        return getattr(getattr(CONF, '%s_client' % client), option)

    @exception.wrap_keystone_exception
    def keystone(self):
        if self._keystone:
            return self._keystone
        keystone_interface = self._get_client_option('keystone',
                                                     'interface')
        keystone_region_name = self._get_client_option('keystone',
                                                       'region_name')
        self._keystone = keyclient.Client(
            interface=keystone_interface,
            region_name=keystone_region_name,
            session=self.session)

        return self._keystone

    @exception.wrap_keystone_exception
    def nova(self):
        if self._nova:
            return self._nova

        novaclient_version = self._get_client_option('nova', 'api_version')

        check_min_nova_api_version(novaclient_version)

        nova_endpoint_type = self._get_client_option('nova', 'endpoint_type')
        nova_region_name = self._get_client_option('nova', 'region_name')
        self._nova = nvclient.Client(novaclient_version,
                                     endpoint_type=nova_endpoint_type,
                                     region_name=nova_region_name,
                                     session=self.session)
        return self._nova

    @exception.wrap_keystone_exception
    def glance(self):
        if self._glance:
            return self._glance

        glanceclient_version = self._get_client_option('glance', 'api_version')
        glance_endpoint_type = self._get_client_option('glance',
                                                       'endpoint_type')
        glance_region_name = self._get_client_option('glance', 'region_name')
        self._glance = glclient.Client(glanceclient_version,
                                       interface=glance_endpoint_type,
                                       region_name=glance_region_name,
                                       session=self.session)
        return self._glance

    @exception.wrap_keystone_exception
    def gnocchi(self):
        if self._gnocchi:
            return self._gnocchi

        gnocchiclient_version = self._get_client_option('gnocchi',
                                                        'api_version')
        gnocchiclient_interface = self._get_client_option('gnocchi',
                                                          'endpoint_type')
        gnocchiclient_region_name = self._get_client_option('gnocchi',
                                                            'region_name')
        adapter_options = {
            "interface": gnocchiclient_interface,
            "region_name": gnocchiclient_region_name
        }

        self._gnocchi = gnclient.Client(gnocchiclient_version,
                                        adapter_options=adapter_options,
                                        session=self.session)
        return self._gnocchi

    @exception.wrap_keystone_exception
    def cinder(self):
        if self._cinder:
            return self._cinder

        cinderclient_version = self._get_client_option('cinder', 'api_version')
        cinder_endpoint_type = self._get_client_option('cinder',
                                                       'endpoint_type')
        cinder_region_name = self._get_client_option('cinder', 'region_name')
        self._cinder = ciclient.Client(cinderclient_version,
                                       endpoint_type=cinder_endpoint_type,
                                       region_name=cinder_region_name,
                                       session=self.session)
        return self._cinder

    @exception.wrap_keystone_exception
    def ceilometer(self):
        if self._ceilometer:
            return self._ceilometer

        ceilometerclient_version = self._get_client_option('ceilometer',
                                                           'api_version')
        ceilometer_endpoint_type = self._get_client_option('ceilometer',
                                                           'endpoint_type')
        ceilometer_region_name = self._get_client_option('ceilometer',
                                                         'region_name')
        self._ceilometer = ceclient.get_client(
            ceilometerclient_version,
            endpoint_type=ceilometer_endpoint_type,
            region_name=ceilometer_region_name,
            session=self.session)
        return self._ceilometer

    @exception.wrap_keystone_exception
    def monasca(self):
        if self._monasca:
            return self._monasca

        monascaclient_version = self._get_client_option(
            'monasca', 'api_version')
        monascaclient_interface = self._get_client_option(
            'monasca', 'interface')
        monascaclient_region = self._get_client_option(
            'monasca', 'region_name')
        token = self.session.get_token()
        watcher_clients_auth_config = CONF.get(_CLIENTS_AUTH_GROUP)
        service_type = 'monitoring'
        monasca_kwargs = {
            'auth_url': watcher_clients_auth_config.auth_url,
            'cert_file': watcher_clients_auth_config.certfile,
            'insecure': watcher_clients_auth_config.insecure,
            'key_file': watcher_clients_auth_config.keyfile,
            'keystone_timeout': watcher_clients_auth_config.timeout,
            'os_cacert': watcher_clients_auth_config.cafile,
            'service_type': service_type,
            'token': token,
            'username': watcher_clients_auth_config.username,
            'password': watcher_clients_auth_config.password,
        }
        endpoint = self.session.get_endpoint(service_type=service_type,
                                             interface=monascaclient_interface,
                                             region_name=monascaclient_region)

        self._monasca = monclient.Client(
            monascaclient_version, endpoint, **monasca_kwargs)

        return self._monasca

    @exception.wrap_keystone_exception
    def neutron(self):
        if self._neutron:
            return self._neutron

        neutronclient_version = self._get_client_option('neutron',
                                                        'api_version')
        neutron_endpoint_type = self._get_client_option('neutron',
                                                        'endpoint_type')
        neutron_region_name = self._get_client_option('neutron', 'region_name')

        self._neutron = netclient.Client(neutronclient_version,
                                         endpoint_type=neutron_endpoint_type,
                                         region_name=neutron_region_name,
                                         session=self.session)
        self._neutron.format = 'json'
        return self._neutron

    @exception.wrap_keystone_exception
    def ironic(self):
        if self._ironic:
            return self._ironic

        ironicclient_version = self._get_client_option('ironic', 'api_version')
        endpoint_type = self._get_client_option('ironic', 'endpoint_type')
        ironic_region_name = self._get_client_option('ironic', 'region_name')
        self._ironic = irclient.get_client(ironicclient_version,
                                           interface=endpoint_type,
                                           region_name=ironic_region_name,
                                           session=self.session)
        return self._ironic

    @exception.wrap_keystone_exception
    def placement(self):
        if self._placement:
            return self._placement

        placement_version = self._get_client_option('placement',
                                                    'api_version')
        placement_interface = self._get_client_option('placement',
                                                      'interface')
        placement_region_name = self._get_client_option('placement',
                                                        'region_name')
        # Set accept header on every request to ensure we notify placement
        # service of our response body media type preferences.
        headers = {'accept': 'application/json'}
        self._placement = ka_adapter.Adapter(
            session=self.session,
            service_type='placement',
            default_microversion=placement_version,
            interface=placement_interface,
            region_name=placement_region_name,
            additional_headers=headers)

        return self._placement
