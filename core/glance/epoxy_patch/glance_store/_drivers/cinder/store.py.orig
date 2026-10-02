#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

"""Storage backend for Cinder"""

import contextlib
import errno
import importlib
import logging
import math
import os
import shlex
import socket
import time

from keystoneauth1.access import service_catalog as keystone_sc
from keystoneauth1 import exceptions as keystone_exc
from keystoneauth1 import identity as ksa_identity
from keystoneauth1 import session as ksa_session
from keystoneauth1 import token_endpoint as ksa_token_endpoint
from oslo_concurrency import processutils
from oslo_config import cfg
from oslo_utils import strutils
from oslo_utils import units

from glance_store._drivers.cinder import base
from glance_store import capabilities
from glance_store.common import attachment_state_manager
from glance_store.common import cinder_utils
from glance_store.common import utils
import glance_store.driver
from glance_store import exceptions
from glance_store.i18n import _, _LE, _LI, _LW
import glance_store.location

try:
    from cinderclient import api_versions
    from cinderclient import exceptions as cinder_exception
    from cinderclient.v3 import client as cinderclient
    import os_brick
    from os_brick.initiator import connector
    from oslo_privsep import priv_context
except ImportError:
    api_versions = None
    cinder_exception = None
    cinderclient = None
    os_brick = None
    connector = None
    priv_context = None


CONF = cfg.CONF
LOG = logging.getLogger(__name__)

_CINDER_OPTS = [
    cfg.StrOpt('cinder_catalog_info',
               default='volumev3::publicURL',
               help="""
Information to match when looking for cinder in the service catalog.

When the ``cinder_endpoint_template`` is not set and any of
``cinder_store_auth_address``, ``cinder_store_user_name``,
``cinder_store_project_name``, ``cinder_store_password`` is not set,
cinder store uses this information to lookup cinder endpoint from the service
catalog in the current context. ``cinder_os_region_name``, if set, is taken
into consideration to fetch the appropriate endpoint.

The service catalog can be listed by the ``openstack catalog list`` command.

Possible values:
    * A string of of the following form:
      ``<service_type>:<service_name>:<interface>``
      At least ``service_type`` and ``interface`` should be specified.
      ``service_name`` can be omitted.

Related options:
    * cinder_os_region_name
    * cinder_endpoint_template
    * cinder_store_auth_address
    * cinder_store_user_name
    * cinder_store_project_name
    * cinder_store_password
    * cinder_store_project_domain_name
    * cinder_store_user_domain_name

"""),
    cfg.StrOpt('cinder_endpoint_template',
               default=None,
               help="""
Override service catalog lookup with template for cinder endpoint.

When this option is set, this value is used to generate cinder endpoint,
instead of looking up from the service catalog.
This value is ignored if ``cinder_store_auth_address``,
``cinder_store_user_name``, ``cinder_store_project_name``, and
``cinder_store_password`` are specified.

If this configuration option is set, ``cinder_catalog_info`` will be ignored.

Possible values:
    * URL template string for cinder endpoint, where ``%%(tenant)s`` is
      replaced with the current tenant (project) name.
      For example: ``http://cinder.openstack.example.org/v2/%%(tenant)s``

Related options:
    * cinder_store_auth_address
    * cinder_store_user_name
    * cinder_store_project_name
    * cinder_store_password
    * cinder_store_project_domain_name
    * cinder_store_user_domain_name
    * cinder_catalog_info

"""),
    cfg.StrOpt('cinder_os_region_name', deprecated_name='os_region_name',
               default=None,
               help="""
Region name to lookup cinder service from the service catalog.

This is used only when ``cinder_catalog_info`` is used for determining the
endpoint. If set, the lookup for cinder endpoint by this node is filtered to
the specified region. It is useful when multiple regions are listed in the
catalog. If this is not set, the endpoint is looked up from every region.

Possible values:
    * A string that is a valid region name.

Related options:
    * cinder_catalog_info

"""),
    cfg.StrOpt('cinder_ca_certificates_file',
               help="""
Location of a CA certificates file used for cinder client requests.

The specified CA certificates file, if set, is used to verify cinder
connections via HTTPS endpoint. If the endpoint is HTTP, this value is ignored.
``cinder_api_insecure`` must be set to ``True`` to enable the verification.

Possible values:
    * Path to a ca certificates file

Related options:
    * cinder_api_insecure

"""),
    cfg.IntOpt('cinder_http_retries',
               min=0,
               default=3,
               help="""
Number of cinderclient retries on failed http calls.

When a call failed by any errors, cinderclient will retry the call up to the
specified times after sleeping a few seconds.

Possible values:
    * A positive integer

Related options:
    * None

"""),
    cfg.IntOpt('cinder_state_transition_timeout',
               min=0,
               default=300,
               help="""
Time period, in seconds, to wait for a cinder volume transition to
complete.

When the cinder volume is created, deleted, or attached to the glance node to
read/write the volume data, the volume's state is changed. For example, the
newly created volume status changes from ``creating`` to ``available`` after
the creation process is completed. This specifies the maximum time to wait for
the status change. If a timeout occurs while waiting, or the status is changed
to an unexpected value (e.g. `error``), the image creation fails.

Possible values:
    * A positive integer

Related options:
    * None

"""),
    cfg.BoolOpt('cinder_api_insecure',
                default=False,
                help="""
Allow to perform insecure SSL requests to cinder.

If this option is set to True, HTTPS endpoint connection is verified using the
CA certificates file specified by ``cinder_ca_certificates_file`` option.

Possible values:
    * True
    * False

Related options:
    * cinder_ca_certificates_file

"""),
    cfg.StrOpt('cinder_store_auth_address',
               default=None,
               help="""
The address where the cinder authentication service is listening.

When all of ``cinder_store_auth_address``, ``cinder_store_user_name``,
``cinder_store_project_name``, and ``cinder_store_password`` options are
specified, the specified values are always used for the authentication.
This is useful to hide the image volumes from users by storing them in a
project/tenant specific to the image service. It also enables users to share
the image volume among other projects under the control of glance's ACL.

If either of these options are not set, the cinder endpoint is looked up
from the service catalog, and current context's user and project are used.

Possible values:
    * A valid authentication service address, for example:
      ``http://openstack.example.org/identity/v2.0``

Related options:
    * cinder_store_user_name
    * cinder_store_password
    * cinder_store_project_name
    * cinder_store_project_domain_name
    * cinder_store_user_domain_name

"""),
    cfg.StrOpt('cinder_store_user_name',
               default=None,
               help="""
User name to authenticate against cinder.

This must be used with all the following non-domain-related options.
If any of these are not specified (except domain-related options),
the user of the current context is used.

Possible values:
    * A valid user name

Related options:
    * cinder_store_auth_address
    * cinder_store_password
    * cinder_store_project_name
    * cinder_store_project_domain_name
    * cinder_store_user_domain_name

"""),
    cfg.StrOpt('cinder_store_user_domain_name',
               default='Default',
               help="""
Domain of the user to authenticate against cinder.

Possible values:
    * A valid domain name for the user specified by ``cinder_store_user_name``

Related options:
    * cinder_store_auth_address
    * cinder_store_password
    * cinder_store_project_name
    * cinder_store_project_domain_name
    * cinder_store_user_name

"""),
    cfg.StrOpt('cinder_store_password', secret=True,
               help="""
Password for the user authenticating against cinder.

This must be used with all the following related options.
If any of these are not specified (except domain-related options),
the user of the current context is used.

Possible values:
    * A valid password for the user specified by ``cinder_store_user_name``

Related options:
    * cinder_store_auth_address
    * cinder_store_user_name
    * cinder_store_project_name
    * cinder_store_project_domain_name
    * cinder_store_user_domain_name

"""),
    cfg.StrOpt('cinder_store_project_name',
               default=None,
               help="""
Project name where the image volume is stored in cinder.

If this configuration option is not set, the project in current context is
used.

This must be used with all the following related options.
If any of these are not specified (except domain-related options),
the user of the current context is used.

Possible values:
    * A valid project name

Related options:
    * ``cinder_store_auth_address``
    * ``cinder_store_user_name``
    * ``cinder_store_password``
    * ``cinder_store_project_domain_name``
    * ``cinder_store_user_domain_name``

"""),
    cfg.StrOpt('cinder_store_project_domain_name',
               default='Default',
               help="""
Domain of the project where the image volume is stored in cinder.

Possible values:
    * A valid domain name of the project specified by
      ``cinder_store_project_name``

Related options:
    * ``cinder_store_auth_address``
    * ``cinder_store_user_name``
    * ``cinder_store_password``
    * ``cinder_store_project_domain_name``
    * ``cinder_store_user_domain_name``

"""),
    cfg.StrOpt('rootwrap_config',
               default='/etc/glance/rootwrap.conf',
               help="""
Path to the rootwrap configuration file to use for running commands as root.

The cinder store requires root privileges to operate the image volumes (for
connecting to iSCSI/FC volumes and reading/writing the volume data, etc.).
The configuration file should allow the required commands by cinder store and
os-brick library.

Possible values:
    * Path to the rootwrap config file

Related options:
    * None

"""),
    cfg.StrOpt('cinder_volume_type',
               default=None,
               help="""
Volume type that will be used for volume creation in cinder.

Some cinder backends can have several volume types to optimize storage usage.
Adding this option allows an operator to choose a specific volume type
in cinder that can be optimized for images.

If this is not set, then the default volume type specified in the cinder
configuration will be used for volume creation.

Possible values:
    * A valid volume type from cinder

Related options:
    * None

NOTE: You cannot use an encrypted volume_type associated with an NFS backend.
An encrypted volume stored on an NFS backend will raise an exception whenever
glance_store tries to write or access image data stored in that volume.
Consult your Cinder administrator to determine an appropriate volume_type.

"""),
    cfg.BoolOpt('cinder_enforce_multipath',
                default=False,
                help="""
If this is set to True, attachment of volumes for image transfer will
be aborted when multipathd is not running. Otherwise, it will fallback
to single path.

Possible values:
    * True or False

Related options:
    * cinder_use_multipath

"""),
    cfg.BoolOpt('cinder_use_multipath',
                default=False,
                help="""
Flag to identify multipath is supported or not in the deployment.

Set it to False if multipath is not supported.

Possible values:
    * True or False

Related options:
    * cinder_enforce_multipath

"""),
    cfg.StrOpt('cinder_mount_point_base',
               default='/var/lib/glance/mnt',
               help="""
Directory where the NFS volume is mounted on the glance node.

Possible values:

* A string representing absolute path of mount point.
"""),
    cfg.BoolOpt('cinder_do_extend_attached',
                default=False,
                help="""
If this is set to True, glance will perform an extend operation
on the attached volume. Only enable this option if the cinder
backend driver supports the functionality of extending online
(in-use) volumes. Supported from cinder microversion 3.42 and
onwards. By default, it is set to False.

Possible values:
    * True or False

"""),
]

CINDER_SESSION = None


def _reset_cinder_session():
    global CINDER_SESSION
    CINDER_SESSION = None


def get_cinder_session(conf):
    global CINDER_SESSION
    if not CINDER_SESSION:
        auth = ksa_identity.V3Password(
            password=conf.cinder_store_password,
            username=conf.cinder_store_user_name,
            user_domain_name=conf.cinder_store_user_domain_name,
            project_name=conf.cinder_store_project_name,
            project_domain_name=conf.cinder_store_project_domain_name,
            auth_url=conf.cinder_store_auth_address
        )
        if conf.cinder_api_insecure:
            verify = False
        elif conf.cinder_ca_certificates_file:
            verify = conf.cinder_ca_certificates_file
        else:
            verify = True
        CINDER_SESSION = ksa_session.Session(auth=auth, verify=verify)
    return CINDER_SESSION


class StoreLocation(glance_store.location.StoreLocation):

    """Class describing a Cinder URI."""

    def process_specs(self):
        self.scheme = self.specs.get('scheme', 'cinder')
        self.volume_id = self.specs.get('volume_id')

    def get_uri(self):
        if self.backend_group:
            return "cinder://%s/%s" % (self.backend_group,
                                       self.volume_id)
        return "cinder://%s" % self.volume_id

    def parse_uri(self, uri):
        self.validate_schemas(uri, valid_schemas=('cinder://',))

        self.scheme = 'cinder'
        self.volume_id = uri.split('/')[-1]

        if not utils.is_uuid_like(self.volume_id):
            reason = _("URI contains invalid volume ID")
            LOG.info(reason)
            raise exceptions.BadStoreUri(message=reason)


class Store(glance_store.driver.Store):

    """Cinder backend store adapter."""

    _CAPABILITIES = (capabilities.BitMasks.READ_RANDOM |
                     capabilities.BitMasks.WRITE_ACCESS |
                     capabilities.BitMasks.DRIVER_REUSABLE)
    OPTIONS = _CINDER_OPTS
    EXAMPLE_URL = "cinder://<VOLUME_ID>"

    def __init__(self, *args, **kargs):
        super(Store, self).__init__(*args, **kargs)
        # We are importing it here to let the config options load
        # before we use them in the fs_mount file
        self.mount = importlib.import_module('glance_store.common.fs_mount')
        self._set_url_prefix()
        if self.backend_group:
            self.store_conf = getattr(self.conf, self.backend_group)
        else:
            self.store_conf = self.conf.glance_store
        self.volume_api = cinder_utils.API()
        if os_brick:
            os_brick.setup(CONF)
        # The purpose of this map is to store the connector object for a
        # particular volume as we will need to call os-brick extend_volume
        # method for the kernel to realize the new size change after cinder
        # extends the volume
        # We only use it when creating the image so a volume will only have
        # one mapping to a particular connector
        self.volume_connector_map = {}

    def _set_url_prefix(self):
        self._url_prefix = "cinder://"
        if self.backend_group:
            self._url_prefix = "cinder://%s" % self.backend_group

    def configure_add(self):
        """
        Check to verify if the volume types configured for the cinder store
        exist in deployment and if not, log a warning.
        """
        for module_name, module in [('cinderclient', cinderclient),
                                    ('os-brick', os_brick),
                                    ('oslo-privsep', priv_context)]:
            if module is None:
                reason = _("%s is not available." % module_name)
                LOG.error(reason)
                raise exceptions.BadStoreConfiguration(store_name="cinder",
                                                       reason=reason)

        cinder_volume_type = self.store_conf.cinder_volume_type
        if cinder_volume_type:
            # NOTE: `cinder_volume_type` is configured, check
            # configured volume_type is available in cinder or not
            cinder_client = self.get_cinderclient()
            try:
                # We don't even need the volume type object, as long
                # as this returns clean, we know the name is good.
                cinder_client.volume_types.find(name=cinder_volume_type)
                # No need to worry about a NoUniqueMatch as volume type name
                # is unique
            except cinder_exception.NotFound:
                reason = (_LW("Invalid `cinder_volume_type %s`"
                              % cinder_volume_type))
                LOG.warning(reason)
            except cinder_exception.ClientException:
                pass

    def is_image_associated_with_store(self, context, volume_id):
        """
        Updates legacy images URL to respective stores.
        This method checks the volume type of the volume associated with the
        image against the configured stores. It returns true if the
        cinder_volume_type configured in the store matches with the volume
        type of the image-volume. When cinder_volume_type is not configured
        then the it checks it against default_volume_type set in cinder.
        If above both conditions doesn't meet, it returns false.
        """
        try:
            # We will use either the service credentials defined in
            # config file or the user context credentials
            cinder_client = self.get_cinderclient(context=context)
            cinder_volume_type = self.store_conf.cinder_volume_type
            # Here we are assuming that the volume is stored in the
            # service project or context user's project else this
            # will return NotFound exception.
            # Ideally we should be using service user's credentials
            # defined in the config and the volume should be stored
            # in the service (internal) project else we are opening the
            # image-volume to modification by users which might lead
            # to corruption of image.
            try:
                volume = cinder_client.volumes.get(volume_id)
            except cinder_exception.NotFound:
                reason = (_LW("Image-Volume %s not found. If you have "
                              "upgraded your environment from single store "
                              "to multi store, transfer all your "
                              "Image-Volumes from user projects to service "
                              "project."
                          % volume_id))
                LOG.warning(reason)
                return False
            if cinder_volume_type and volume.volume_type == cinder_volume_type:
                return True
            elif not cinder_volume_type:
                default_type = cinder_client.volume_types.default()
                if volume.volume_type == default_type.name:
                    return True
        except Exception:
            # Glance calls this method to update legacy images URL
            # If an exception occurs due to image/volume is non-existent or
            # any other reason, we return False (i.e. the image location URL
            # won't be updated) and it is glance's responsibility to handle
            # the case when the image failed to update
            pass

        return False

    def get_root_helper(self):
        rootwrap = self.store_conf.rootwrap_config
        return 'sudo glance-rootwrap %s' % rootwrap

    def is_user_overriden(self):
        return all([self.store_conf.get('cinder_store_' + key)
                    for key in ['user_name', 'password',
                                'project_name', 'auth_address']])

    def get_cinderclient(self, context=None, version='3.0'):
        user_overriden = self.is_user_overriden()
        session = get_cinder_session(self.store_conf)

        if user_overriden:
            username = self.store_conf.cinder_store_user_name
            url = self.store_conf.cinder_store_auth_address
            # use auth that is already in the session
            auth = None
        else:
            username = context.user_id
            project = context.project_id
            # noauth extracts user_id:project_id from auth_token
            token = context.auth_token or '%s:%s' % (username, project)

            if self.store_conf.cinder_endpoint_template:
                template = self.store_conf.cinder_endpoint_template
                url = template % context.to_dict()
            else:
                info = self.store_conf.cinder_catalog_info
                service_type, service_name, interface = info.split(':')
                try:
                    catalog = keystone_sc.ServiceCatalogV2(
                        context.service_catalog)
                    url = catalog.url_for(
                        region_name=self.store_conf.cinder_os_region_name,
                        service_type=service_type,
                        service_name=service_name,
                        interface=interface)
                except keystone_exc.EndpointNotFound:
                    reason = _("Failed to find Cinder from a service catalog.")
                    raise exceptions.BadStoreConfiguration(store_name="cinder",
                                                           reason=reason)
            auth = ksa_token_endpoint.Token(endpoint=url, token=token)

        api_version = api_versions.APIVersion(version)
        c = cinderclient.Client(
            session=session, auth=auth,
            region_name=self.store_conf.cinder_os_region_name,
            retries=self.store_conf.cinder_http_retries,
            api_version=api_version)

        LOG.debug(
            'Cinderclient connection created for user %(user)s using URL: '
            '%(url)s.', {'user': username, 'url': url})

        return c

    @contextlib.contextmanager
    def temporary_chown(self, path):
        owner_uid = os.getuid()
        orig_uid = os.stat(path).st_uid

        if orig_uid != owner_uid:
            processutils.execute(
                'chown', owner_uid, path,
                run_as_root=True,
                root_helper=self.get_root_helper())
        try:
            yield
        finally:
            if orig_uid != owner_uid:
                processutils.execute(
                    'chown', orig_uid, path,
                    run_as_root=True,
                    root_helper=self.get_root_helper())

    def get_schemes(self):
        return ('cinder',)

    def _check_context(self, context, require_tenant=False):
        user_overriden = self.is_user_overriden()
        if user_overriden and not require_tenant:
            return
        if context is None:
            reason = _("Cinder storage requires a context.")
            raise exceptions.BadStoreConfiguration(store_name="cinder",
                                                   reason=reason)
        if not user_overriden and context.service_catalog is None:
            reason = _("Cinder storage requires a service catalog.")
            raise exceptions.BadStoreConfiguration(store_name="cinder",
                                                   reason=reason)

    def _wait_volume_status(self, volume, status_transition, status_expected):
        max_recheck_wait = 15
        timeout = self.store_conf.cinder_state_transition_timeout
        volume = volume.manager.get(volume.id)
        tries = 0
        elapsed = 0
        while volume.status == status_transition:
            if elapsed >= timeout:
                msg = (_('Timeout while waiting while volume %(volume_id)s '
                         'status is %(status)s.')
                       % {'volume_id': volume.id, 'status': status_transition})
                LOG.error(msg)
                raise exceptions.BackendException(msg)

            wait = min(0.5 * 2 ** tries, max_recheck_wait)
            time.sleep(wait)
            tries += 1
            elapsed += wait
            volume = volume.manager.get(volume.id)
        if volume.status != status_expected:
            msg = (_('The status of volume %(volume_id)s is unexpected: '
                     'status = %(status)s, expected = %(expected)s.')
                   % {'volume_id': volume.id, 'status': volume.status,
                      'expected': status_expected})
            LOG.error(msg)
            raise exceptions.BackendException(msg)
        return volume

    def _get_host_ip(self, host):
        try:
            return socket.getaddrinfo(host, None, socket.AF_INET6)[0][4][0]
        except socket.gaierror:
            return socket.getaddrinfo(host, None, socket.AF_INET)[0][4][0]

    @contextlib.contextmanager
    def _open_cinder_volume(self, client, volume, mode):
        attach_mode = 'rw' if mode == 'wb' else 'ro'
        device = None
        root_helper = self.get_root_helper()
        priv_context.init(root_helper=shlex.split(root_helper))
        host = socket.gethostname()
        my_ip = self._get_host_ip(host)
        use_multipath = self.store_conf.cinder_use_multipath
        enforce_multipath = self.store_conf.cinder_enforce_multipath
        volume_id = volume.id

        connector_prop = connector.get_connector_properties(
            root_helper, my_ip, use_multipath, enforce_multipath, host=host)

        if volume.multiattach:
            attachment = attachment_state_manager.attach(client, volume_id,
                                                         host,
                                                         mode=attach_mode)
        else:
            attachment = self.volume_api.attachment_create(client, volume_id,
                                                           mode=attach_mode)
        LOG.debug('Attachment %(attachment_id)s created successfully.',
                  {'attachment_id': attachment['id']})

        volume = volume.manager.get(volume_id)
        attachment_id = attachment['id']
        connection_info = None
        try:
            attachment = self.volume_api.attachment_update(
                client, attachment_id, connector_prop,
                mountpoint='glance_store')
            LOG.debug('Attachment %(attachment_id)s updated successfully with '
                      'connection info %(conn_info)s',
                      {'attachment_id': attachment_id,
                       'conn_info': strutils.mask_dict_password(
                           attachment.connection_info)})
            connection_info = attachment.connection_info
            conn = base.factory(
                connection_info['driver_volume_type'],
                volume=volume,
                connection_info=connection_info,
                root_helper=root_helper,
                use_multipath=use_multipath,
                mountpoint_base=self.store_conf.cinder_mount_point_base,
                attachment_obj=attachment,
                client=client)
            device = conn.connect_volume(volume)

            # Complete the attachment (marking the volume "in-use") after
            # the connection with os-brick is complete
            self.volume_api.attachment_complete(client, attachment_id)
            LOG.debug('Attachment %(attachment_id)s completed successfully.',
                      {'attachment_id': attachment_id})

            self.volume_connector_map[volume.id] = conn
            if (connection_info['driver_volume_type'] == 'rbd' and
               not conn.conn.do_local_attach):
                yield device['path']
            else:
                with self.temporary_chown(
                        device['path']), open(device['path'], mode) as f:
                    yield conn.yield_path(volume, f)
        except Exception:
            LOG.exception(_LE('Exception while accessing to cinder volume '
                              '%(volume_id)s.'), {'volume_id': volume.id})
            raise
        finally:
            if device:
                try:
                    if volume.multiattach:
                        attachment_state_manager.detach(
                            client, attachment_id, volume_id, host, conn,
                            connection_info, device)
                    else:
                        conn.disconnect_volume(device)
                        if self.volume_connector_map.get(volume.id):
                            del self.volume_connector_map[volume.id]
                except Exception:
                    LOG.exception(_LE('Failed to disconnect volume '
                                      '%(volume_id)s.'),
                                  {'volume_id': volume.id})

            if not volume.multiattach:
                self.volume_api.attachment_delete(client, attachment_id)

    def _cinder_volume_data_iterator(self, client, volume, max_size, offset=0,
                                     chunk_size=None, partial_length=None):
        chunk_size = chunk_size if chunk_size else self.READ_CHUNKSIZE
        partial = partial_length is not None
        with self._open_cinder_volume(client, volume, 'rb') as fp:
            if offset:
                fp.seek(offset)
                max_size -= offset
            while True:
                if partial:
                    size = min(chunk_size, partial_length, max_size)
                else:
                    size = min(chunk_size, max_size)

                chunk = fp.read(size)
                if chunk:
                    yield chunk
                    max_size -= len(chunk)
                    if max_size <= 0:
                        break
                    if partial:
                        partial_length -= len(chunk)
                        if partial_length <= 0:
                            break
                else:
                    break

    @capabilities.check
    def get(self, location, offset=0, chunk_size=None, context=None):
        """
        Takes a `glance_store.location.Location` object that indicates
        where to find the image file, and returns a tuple of generator
        (for reading the image file) and image_size

        :param location: `glance_store.location.Location` object, supplied
                        from glance_store.location.get_location_from_uri()
        :param offset: offset to start reading
        :param chunk_size: size to read, or None to get all the image
        :param context: Request context
        :raises: `glance_store.exceptions.NotFound` if image does not exist
        """

        loc = location.store_location
        self._check_context(context)
        try:
            client = self.get_cinderclient(context, version='3.54')
            volume = client.volumes.get(loc.volume_id)
            size = int(volume.metadata.get('image_size',
                                           volume.size * units.Gi))
            iterator = self._cinder_volume_data_iterator(
                client, volume, size, offset=offset,
                chunk_size=self.READ_CHUNKSIZE, partial_length=chunk_size)
            return (iterator, chunk_size or size)
        except cinder_exception.NotFound:
            reason = _("Failed to get image size due to "
                       "volume can not be found: %s") % loc.volume_id
            LOG.error(reason)
            raise exceptions.NotFound(reason)
        except cinder_exception.ClientException as e:
            msg = (_('Failed to get image volume %(volume_id)s: %(error)s')
                   % {'volume_id': loc.volume_id, 'error': e})
            LOG.error(msg)
            raise exceptions.BackendException(msg)

    def get_size(self, location, context=None):
        """
        Takes a `glance_store.location.Location` object that indicates
        where to find the image file and returns the image size

        :param location: `glance_store.location.Location` object, supplied
                        from glance_store.location.get_location_from_uri()
        :raises: `glance_store.exceptions.NotFound` if image does not exist
        :rtype: int
        """

        loc = location.store_location

        try:
            self._check_context(context)
            volume = self.get_cinderclient(context).volumes.get(loc.volume_id)
            return int(volume.metadata.get('image_size',
                                           volume.size * units.Gi))
        except cinder_exception.NotFound:
            raise exceptions.NotFound(image=loc.volume_id)
        except Exception:
            LOG.exception(_LE("Failed to get image size due to "
                              "internal error."))
            return 0

    def _call_offline_extend(self, volume, size_gb):
        size_gb += 1
        LOG.debug("Extending (offline) volume %(volume_id)s to %(size)s GB.",
                  {'volume_id': volume.id, 'size': size_gb})
        volume.extend(volume, size_gb)
        try:
            volume = self._wait_volume_status(volume,
                                              'extending',
                                              'available')
            size_gb = volume.size
            return size_gb
        except exceptions.BackendException:
            raise exceptions.StorageFull()

    def _call_online_extend(self, client, volume, size_gb):
        size_gb += 1
        LOG.debug("Extending (online) volume %(volume_id)s to %(size)s GB.",
                  {'volume_id': volume.id, 'size': size_gb})
        self.volume_api.extend_volume(client, volume, size_gb)
        try:
            volume = self._wait_volume_status(volume,
                                              'extending',
                                              'in-use')
            size_gb = volume.size
            return size_gb
        except exceptions.BackendException:
            raise exceptions.StorageFull()

    def _write_data(self, f, write_props):
        LOG.debug('Writing data to volume with write properties: '
                  'bytes_written: %s, size_gb: %s, need_extend: %s, '
                  'image_size: %s' %
                  (write_props.bytes_written, write_props.size_gb,
                   write_props.need_extend, write_props.image_size))
        f.seek(write_props.bytes_written)
        if write_props.buf:
            f.write(write_props.buf)
            write_props.bytes_written += len(write_props.buf)
        while True:
            write_props.buf = write_props.image_file.read(
                self.WRITE_CHUNKSIZE)
            if not write_props.buf:
                write_props.need_extend = False
                return
            write_props.os_hash_value.update(write_props.buf)
            write_props.checksum.update(write_props.buf)
            if write_props.verifier:
                write_props.verifier.update(write_props.buf)
            if ((write_props.bytes_written + len(write_props.buf)) > (
                write_props.size_gb * units.Gi) and
                    (write_props.image_size == 0)):
                return
            f.write(write_props.buf)
            write_props.bytes_written += len(write_props.buf)

    def _offline_extend(self, client, volume, write_props):
        while write_props.need_extend:
            with self._open_cinder_volume(client, volume, 'wb') as f:
                self._write_data(f, write_props)
            if write_props.need_extend:
                write_props.size_gb = self._call_offline_extend(
                    volume, write_props.size_gb)

    def _online_extend(self, client, volume, write_props):
        with self._open_cinder_volume(client, volume, 'wb') as f:
            # Th connector is initialized in _open_cinder_volume method
            # and by mapping it with the volume ID, we are able to fetch
            # it here
            conn = self.volume_connector_map[volume.id]
            while write_props.need_extend:
                self._write_data(f, write_props)
                if write_props.need_extend:
                    # we already initialize a client with MV 3.54 and
                    # we require 3.42 for online extend so we should
                    # be good here.
                    write_props.size_gb = self._call_online_extend(
                        client, volume, write_props.size_gb)
                    # Call os-brick to resize the LUN on the host
                    conn.extend_volume()

    # WriteProperties class is useful to allow us to modify immutable
    # objects in the called methods
    class WriteProperties:
        def __init__(self, *args, **kwargs):
            self.bytes_written = kwargs.get('bytes_written')
            self.size_gb = kwargs.get('size_gb')
            self.buf = kwargs.get('buf')
            self.image_file = kwargs.get('image_file')
            self.need_extend = kwargs.get('need_extend')
            self.image_size = kwargs.get('image_size')
            self.verifier = kwargs.get('verifier')
            self.checksum = kwargs.get('checksum')
            self.os_hash_value = kwargs.get('os_hash_value')

    @glance_store.driver.back_compat_add
    @capabilities.check
    def add(self, image_id, image_file, image_size, hashing_algo, context=None,
            verifier=None):
        """
        Stores an image file with supplied identifier to the backend
        storage system and returns a tuple containing information
        about the stored image.

        :param image_id: The opaque image identifier
        :param image_file: The image data to write, as a file-like object
        :param image_size: The size of the image data to write, in bytes
        :param hashing_algo: A hashlib algorithm identifier (string)
        :param context: The request context
        :param verifier: An object used to verify signatures for images

        :returns: tuple of: (1) URL in backing store, (2) bytes written,
                  (3) checksum, (4) multihash value, and (5) a dictionary
                  with storage system specific information
        :raises: `glance_store.exceptions.Duplicate` if the image already
                 exists
        """

        self._check_context(context, require_tenant=True)
        client = self.get_cinderclient(context, version='3.54')
        os_hash_value = utils.get_hasher(hashing_algo, False)
        checksum = utils.get_hasher('md5', False)
        bytes_written = 0
        size_gb = int(math.ceil(float(image_size) / units.Gi))
        if size_gb == 0:
            size_gb = 1
        name = "image-%s" % image_id
        owner = context.project_id
        metadata = {'glance_image_id': image_id,
                    'image_size': str(image_size),
                    'image_owner': owner}

        volume_type = self.store_conf.cinder_volume_type

        LOG.debug('Creating a new volume: image_size=%d size_gb=%d type=%s',
                  image_size, size_gb, volume_type or 'None')
        if image_size == 0:
            LOG.info(_LI("Since image size is zero, we will be doing "
                         "resize-before-write for each GB which "
                         "will be considerably slower than normal."))

        volume = self.volume_api.create(client, size_gb, name=name,
                                        metadata=metadata,
                                        volume_type=volume_type)

        volume = self._wait_volume_status(volume, 'creating', 'available')
        size_gb = volume.size

        failed = True
        need_extend = True
        buf = None
        online_extend = self.store_conf.cinder_do_extend_attached
        write_props = self.WriteProperties(
            bytes_written=bytes_written, size_gb=size_gb, buf=buf,
            image_file=image_file, need_extend=need_extend,
            image_size=image_size, verifier=verifier, checksum=checksum,
            os_hash_value=os_hash_value)
        try:
            if online_extend:
                # we already initialize a client with MV 3.54 and
                # we require 3.42 for online extend so we should
                # be good here.
                self._online_extend(client, volume, write_props)
            else:
                self._offline_extend(client, volume, write_props)
            failed = False
        except IOError as e:
            # Convert IOError reasons to Glance Store exceptions
            errors = {errno.EFBIG: exceptions.StorageFull(),
                      errno.ENOSPC: exceptions.StorageFull(),
                      errno.EACCES: exceptions.StorageWriteDenied()}
            raise errors.get(e.errno, e)
        finally:
            if failed:
                LOG.error(_LE("Failed to write to volume %(volume_id)s."),
                          {'volume_id': volume.id})
                try:
                    volume.delete()
                except Exception:
                    LOG.exception(_LE('Failed to delete of volume '
                                      '%(volume_id)s.'),
                                  {'volume_id': volume.id})

        if write_props.image_size == 0:
            metadata.update({'image_size': str(write_props.bytes_written)})
            volume.update_all_metadata(metadata)
        volume.update_readonly_flag(volume, True)

        hash_hex = write_props.os_hash_value.hexdigest()
        checksum_hex = write_props.checksum.hexdigest()

        LOG.debug("Wrote %(bytes_written)d bytes to volume %(volume_id)s "
                  "with checksum %(checksum_hex)s.",
                  {'bytes_written': write_props.bytes_written,
                   'volume_id': volume.id,
                   'checksum_hex': checksum_hex})

        image_metadata = {}
        location_url = 'cinder://%s' % volume.id
        if self.backend_group:
            image_metadata['store'] = self.backend_group
            location_url = 'cinder://%s/%s' % (self.backend_group,
                                               volume.id)

        return (location_url,
                write_props.bytes_written,
                checksum_hex,
                hash_hex,
                image_metadata)

    @capabilities.check
    def delete(self, location, context=None):
        """
        Takes a `glance_store.location.Location` object that indicates
        where to find the image file to delete

        :param location: `glance_store.location.Location` object, supplied
                  from glance_store.location.get_location_from_uri()

        :raises: NotFound if image does not exist
        :raises: Forbidden if cannot delete because of permissions
        """
        loc = location.store_location
        self._check_context(context)
        client = self.get_cinderclient(context)
        try:
            self.volume_api.delete(client, loc.volume_id)
        except cinder_exception.NotFound:
            raise exceptions.NotFound(image=loc.volume_id)
        except cinder_exception.ClientException as e:
            msg = (_('Failed to delete volume %(volume_id)s: %(error)s') %
                   {'volume_id': loc.volume_id, 'error': e})
            raise exceptions.BackendException(msg)
