# Copyright 2019 Intel, Inc.
# All Rights Reserved.
#
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

"""Version 2 of the Cyborg API"""

import pecan
from pecan import rest
from webob import exc
from wsme import types as wtypes

from cyborg.api import expose

from cyborg.api.controllers import base
from cyborg.api.controllers import link
from cyborg.api.controllers.v2 import arqs
from cyborg.api.controllers.v2 import attributes
from cyborg.api.controllers.v2 import deployables
from cyborg.api.controllers.v2 import device_profiles
from cyborg.api.controllers.v2 import devices

from cyborg.api.controllers.v2 import versions


def min_version():
    return base.Version(
        {base.Version.current_api_version: versions.min_version_string()},
        versions.min_version_string(), versions.max_version_string())


def max_version():
    return base.Version(
        {base.Version.current_api_version: versions.max_version_string()},
        versions.min_version_string(), versions.max_version_string())


class V2(base.APIBase):
    """The representation of the version 2 of the API."""

    id = wtypes.text
    """The ID of the version"""

    links = [link.Link]
    """Links to the accelerator resource"""

    max_version = wtypes.text
    """Highest microversion supported"""

    min_version = wtypes.text
    """Lowest microversion supported"""

    status = wtypes.text
    """Status"""

    @staticmethod
    def convert():
        v2 = V2()
        v2.id = 'v2.0'
        v2.max_version = str(max_version())
        v2.min_version = str(min_version())
        v2.status = 'CURRENT'
        v2.links = [
            link.Link.make_link('self', pecan.request.public_url,
                                '', ''),
            ]
        return v2


class Controller(rest.RestController):
    """Version 2 API controller root"""

    device_profiles = device_profiles.DeviceProfilesController()
    accelerator_requests = arqs.ARQsController()
    devices = devices.DevicesController()
    deployables = deployables.DeployablesController()
    attributes = attributes.AttributesController()

    @expose.expose(V2)
    def get(self):
        return V2.convert()

    def _check_version(self, version, headers=None):
        if headers is None:
            headers = {}
        # ensure that major version in the URL matches the header
        if version.major != versions.BASE_VERSION:
            raise exc.HTTPNotAcceptable(
                "Mutually exclusive versions requested. Version %(ver)s "
                "requested but not supported by this service. The supported "
                "version range is: [%(min)s, %(max)s]." %
                {'ver': version, 'min': versions.min_version_string(),
                 'max': versions.max_version_string()},
                headers=headers)
        # ensure the minor version is within the supported range
        if version < min_version() or version > max_version():
            raise exc.HTTPNotAcceptable(
                "Version %(ver)s was requested but the minor version is not "
                "supported by this service. The supported version range is: "
                "[%(min)s, %(max)s]." %
                {'ver': version, 'min': versions.min_version_string(),
                 'max': versions.max_version_string()},
                headers=headers)

    @pecan.expose()
    def _route(self, args, request=None):
        v = base.Version(pecan.request.headers, versions.min_version_string(),
                         versions.max_version_string())

        # The Vary header is used as a hint to caching proxies and user agents
        # that the response is also dependent on the OpenStack-API-Version and
        # not just the body and query parameters. See RFC 7231 for details.
        pecan.response.headers['Vary'] = base.Version.current_api_version

        # Always set the min and max headers
        pecan.response.headers[base.Version.min_api_version] = (
            versions.min_version_string())
        pecan.response.headers[base.Version.max_api_version] = (
            versions.max_version_string())

        # assert that requested version is supported
        self._check_version(v, pecan.response.headers)
        pecan.response.headers[base.Version.current_api_version] = str(v)
        pecan.request.version = v

        return super(Controller, self)._route(args, request)


__all__ = ('Controller',)
