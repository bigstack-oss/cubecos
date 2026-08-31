# Copyright 2016 NTT DATA
#
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

"""
Handles all requests to Nova.
"""

import functools
import sys

from keystoneauth1 import exceptions as keystone_exception
import keystoneauth1.loading
import keystoneauth1.loading.session
from novaclient import api_versions
from novaclient import client as nova_client
from novaclient import exceptions as nova_exception
from oslo_log import log as logging
from oslo_utils import encodeutils
from requests import exceptions as request_exceptions

from masakari import conf
from masakari import context as ctx
from masakari import exception
from masakari import utils

CONF = conf.CONF
CONF.import_group('keystone_authtoken', 'keystonemiddleware.auth_token')

LOG = logging.getLogger(__name__)

NOVA_API_VERSION = "2.53"

nova_extensions = [ext for ext in
                   nova_client.discover_extensions(NOVA_API_VERSION)
                   if ext.name in ("list_extensions",)]


def _reraise(desired_exc):
    utils.reraise(type(desired_exc), desired_exc, sys.exc_info()[2])


def translate_nova_exception(method):
    """Transforms a cinder exception but keeps its traceback intact."""
    @functools.wraps(method)
    def wrapper(self, ctx, *args, **kwargs):
        try:
            res = method(self, ctx, *args, **kwargs)
        except (request_exceptions.Timeout,
                nova_exception.CommandError,
                keystone_exception.ConnectionError) as exc:
            err_msg = encodeutils.exception_to_unicode(exc)
            _reraise(exception.MasakariException(reason=err_msg))
        except (keystone_exception.BadRequest,
                nova_exception.BadRequest) as exc:
            err_msg = encodeutils.exception_to_unicode(exc)
            _reraise(exception.InvalidInput(reason=err_msg))
        except (keystone_exception.Forbidden,
                nova_exception.Forbidden) as exc:
            err_msg = encodeutils.exception_to_unicode(exc)
            _reraise(exception.Forbidden(err_msg))
        except (nova_exception.NotFound) as exc:
            err_msg = encodeutils.exception_to_unicode(exc)
            _reraise(exception.NotFound(reason=err_msg))
        except nova_exception.Conflict as exc:
            err_msg = encodeutils.exception_to_unicode(exc)
            _reraise(exception.Conflict(reason=err_msg))
        return res
    return wrapper


def novaclient(context, timeout=None):
    """Returns a Nova client

    @param timeout: Number of seconds to wait for an answer before raising a
        Timeout exception (None to disable)
    """
    nova_catalog_info = CONF.nova_catalog_admin_info
    service_type, service_name, endpoint_type = nova_catalog_info.split(':')

    context = ctx.RequestContext(
        CONF.os_privileged_user_name, None,
        auth_token=CONF.os_privileged_user_password,
        project_name=CONF.os_privileged_user_tenant,
        service_catalog=context.service_catalog,
        global_request_id=context.global_id)

    # User needs to authenticate to Keystone before querying Nova, so we set
    # auth_url to the identity service endpoint
    url = CONF.os_privileged_user_auth_url

    LOG.debug('Creating a Nova client using "%s" user',
              CONF.os_privileged_user_name)

    # Now that we have the correct auth_url, username, password and
    # project_name, let's build a Keystone session.
    loader = keystoneauth1.loading.get_plugin_loader(
        CONF.keystone_authtoken.auth_type)
    auth = loader.load_from_options(
        auth_url=url,
        username=context.user_id,
        password=context.auth_token,
        project_name=context.project_name,
        user_domain_name=CONF.os_user_domain_name,
        project_domain_name=CONF.os_project_domain_name,
        system_scope=CONF.os_system_scope)
    session_loader = keystoneauth1.loading.session.Session()
    keystone_session = session_loader.load_from_options(
        auth=auth, cacert=CONF.nova_ca_certificates_file,
        insecure=CONF.nova_api_insecure)

    client_obj = nova_client.Client(
        api_versions.APIVersion(NOVA_API_VERSION),
        session=keystone_session,
        insecure=CONF.nova_api_insecure,
        timeout=timeout,
        global_request_id=context.global_id,
        region_name=CONF.os_region_name,
        endpoint_type=endpoint_type,
        service_type=service_type,
        service_name=service_name,
        cacert=CONF.nova_ca_certificates_file,
        extensions=nova_extensions)

    return client_obj


class API(object):
    """API for interacting with novaclient."""

    @translate_nova_exception
    def get_servers(self, context, host):
        """Get a list of servers running on a specified host."""
        opts = {
            'host': host,
            'all_tenants': True
        }
        nova = novaclient(context)
        LOG.info('Fetch Server list on %s', host)
        return nova.servers.list(detailed=True, search_opts=opts)

    @translate_nova_exception
    def enable_disable_service(self, context, host_name, enable=False,
                               reason=None):
        """Enable or disable the service specified by nova service id."""
        nova = novaclient(context)
        service = nova.services.list(host=host_name, binary='nova-compute')[0]

        if not enable:
            LOG.info('Disable nova-compute on %s', host_name)
            if reason:
                nova.services.disable_log_reason(service.id, reason)
            else:
                nova.services.disable(service.id)
        else:
            LOG.info('Enable nova-compute on %s', host_name)
            nova.services.enable(service.id)

    @translate_nova_exception
    def is_service_disabled(self, context, host_name, binary):
        """Check whether service is enabled or disabled on given host."""
        nova = novaclient(context)
        service = nova.services.list(host=host_name, binary=binary)[0]
        return service.status == 'disabled'

    @translate_nova_exception
    def evacuate_instance(self, context, uuid, target=None):
        """Evacuate an instance from failed host to specified host."""
        msg = ('Call evacuate command for instance %(uuid)s on host '
               '%(target)s')
        LOG.info(msg, {'uuid': uuid, 'target': target})
        nova = novaclient(context)
        nova.servers.evacuate(uuid, host=target)

    @translate_nova_exception
    def reset_instance_state(self, context, uuid, status='error'):
        """Reset the state of an instance to active or error."""
        msg = ('Call reset state command on instance %(uuid)s to '
               'status: %(status)s.')
        LOG.info(msg, {'uuid': uuid, 'status': status})
        nova = novaclient(context)
        nova.servers.reset_state(uuid, status)

    @translate_nova_exception
    def get_server(self, context, uuid):
        """Get a server."""
        nova = novaclient(context)
        msg = ('Call get server command for instance %(uuid)s')
        LOG.info(msg, {'uuid': uuid})
        return nova.servers.get(uuid)

    @translate_nova_exception
    def stop_server(self, context, uuid):
        """Stop a server."""
        nova = novaclient(context)
        msg = ('Call stop server command for instance %(uuid)s')
        LOG.info(msg, {'uuid': uuid})
        return nova.servers.stop(uuid)

    @translate_nova_exception
    def start_server(self, context, uuid):
        """Start a server."""
        nova = novaclient(context)
        msg = ('Call start server command for instance %(uuid)s')
        LOG.info(msg, {'uuid': uuid})
        return nova.servers.start(uuid)

    @translate_nova_exception
    def get_aggregate_list(self, context):
        """Get all aggregate list."""
        nova = novaclient(context)
        LOG.info('Call aggregate-list command to get list of all aggregates.')
        return nova.aggregates.list()

    @translate_nova_exception
    def add_host_to_aggregate(self, context, host, aggregate):
        """Add host to given aggregate."""
        nova = novaclient(context)
        msg = ("Call add_host command to add host '%(host_name)s' to "
               "aggregate '%(aggregate_name)s'.")
        LOG.info(msg, {'host_name': host, 'aggregate_name': aggregate.name})
        return nova.aggregates.add_host(aggregate.id, host)

    @translate_nova_exception
    def lock_server(self, context, uuid):
        """Lock a server."""
        nova = novaclient(context)
        msg = ('Call lock server command for instance %(uuid)s')
        LOG.info(msg, {'uuid': uuid})
        return nova.servers.lock(uuid)

    @translate_nova_exception
    def unlock_server(self, context, uuid):
        """Unlock a server."""
        nova = novaclient(context)
        msg = ('Call unlock server command for instance %(uuid)s')
        LOG.info(msg, {'uuid': uuid})
        return nova.servers.unlock(uuid)

    @translate_nova_exception
    def find_compute_service(self, context, compute_name):
        """Find compute service with case sensitive hostname."""
        nova = novaclient(context)
        msg = ("Call compute service find command to get list of matching "
               "hypervisor name '%(compute_name)s'")
        LOG.info(msg, {'compute_name': compute_name})

        computes = \
            nova.services.list(binary='nova-compute', host=compute_name)
        if len(computes) == 0:
            raise exception.ComputeNotFoundByName(
                compute_name=compute_name)
