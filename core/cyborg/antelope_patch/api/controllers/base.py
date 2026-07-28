# Copyright 2017 Huawei Technologies Co.,LTD.
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

import datetime
import functools

import inspect
import microversion_parse

import pecan
from pecan import rest
from webob import exc
import wsme
from wsme import types as wtypes

API_V2 = 'v2'
# name of attribute to keep version method information


class APIBase(wtypes.Base):
    created_at = wsme.wsattr(datetime.datetime, readonly=True)
    """The time in UTC at which the object is created"""

    updated_at = wsme.wsattr(datetime.datetime, readonly=True)
    """The time in UTC at which the object is updated"""

    def as_dict(self):
        """Render this object as a dict of its fields."""
        return {k: getattr(self, k) for k in self.fields
                if hasattr(self, k) and getattr(self, k) != wsme.Unset}


class CyborgController(rest.RestController):

    def _handle_patch(self, method, remainder, request=None):
        """Routes ``PATCH`` _custom_actions."""
        # route to a patch_all or get if no additional parts are available
        if not remainder or remainder == ['']:
            controller = self._find_controller('patch_all', 'patch')
            if controller:
                return controller, []
            pecan.abort(404)

        controller = getattr(self, remainder[0], None)
        if controller and not inspect.ismethod(controller):
            return pecan.routing.lookup_controller(controller, remainder[1:])
        # route to custom_action
        match = self._handle_custom_action(method, remainder, request)
        if match:
            return match

        # finally, check for the regular patch_one/patch requests
        controller = self._find_controller('patch_one', 'patch')
        if controller:
            return controller, remainder

        pecan.abort(405)


@functools.total_ordering
class Version(object):
    """API Version object."""

    current_api_version = 'OpenStack-API-Version'
    """HTTP Header string carrying the requested version"""

    min_api_version = 'OpenStack-API-Minimum-Version'
    """HTTP response header"""

    max_api_version = 'OpenStack-API-Maximum-Version'
    """HTTP response header"""

    def __init__(self, headers, default_version, latest_version):
        """Create an API Version object from the supplied headers.

        :param headers: webob headers
        :param default_version: version to use if not specified in headers
        :param latest_version: version to use if latest is requested
        :raises: webob.HTTPNotAcceptable

        """
        (self.major, self.minor) = Version.parse_headers(
            headers, default_version, latest_version)

    def __repr__(self):
        return '%s.%s' % (self.major, self.minor)

    @staticmethod
    def parse_headers(headers, default_version, latest_version):
        """Determine the API version requested based on the headers supplied.

        :param headers: webob headers
        :param default_version: version to use if not specified in headers
        :param latest_version: version to use if latest is requested
        :returns: a tuple of (major, minor) version numbers
        :raises: webob.HTTPNotAcceptable

        """
        version_str = microversion_parse.get_version(
            headers,
            service_type='accelerator')

        minimal_version = (2, 0)

        if version_str is None:
            # If requested header is wrong, Cyborg answers with the minimal
            # supported version.
            return minimal_version

        if version_str.lower() == 'latest':
            parse_str = latest_version
        else:
            parse_str = version_str

        try:
            version = tuple(int(i) for i in parse_str.split('.'))
        except ValueError:
            version = minimal_version

        if len(version) != 2:
            raise exc.HTTPNotAcceptable(
                "Invalid value for %s header" % Version.current_api_version)
        return version

    def __gt__(self, other):
        return (self.major, self.minor) > (other.major, other.minor)

    def __eq__(self, other):
        return (self.major, self.minor) == (other.major, other.minor)

    def __ne__(self, other):
        return not self.__eq__(other)
