# Copyright (c) 2018 NEC, Corp.
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

import sys

from oslo_config import cfg
from oslo_upgradecheck import upgradecheck
from oslo_utils import fileutils

from cyborg.common.i18n import _


CONF = cfg.CONF


class Checks(upgradecheck.UpgradeCommands):

    """Various upgrade checks should be added as separate methods in this class
    and added to _upgrade_checks tuple.
    """

    def _check_policy_json(self):
        "Checks to see if policy file is JSON-formatted policy file."
        msg = _("Your policy file is JSON-formatted which is "
                "deprecated since Victoria release (Cyborg 5.0.0). "
                "You need to switch to YAML-formatted file. You can use the "
                "``oslopolicy-convert-json-to-yaml`` tool to convert existing "
                "JSON-formatted files to YAML-formatted files in a "
                "backwards-compatible manner: "
                "https://docs.openstack.org/oslo.policy/"
                "latest/cli/oslopolicy-convert-json-to-yaml.html.")
        status = upgradecheck.Result(upgradecheck.Code.SUCCESS)
        # NOTE(gmann): Check if policy file exist and is in
        # JSON format by actually loading the file not just
        # by checking the extension.
        policy_path = CONF.find_file(CONF.oslo_policy.policy_file)
        if policy_path and fileutils.is_json(policy_path):
            status = upgradecheck.Result(upgradecheck.Code.FAILURE, msg)
        return status

    # The format of the check functions is to return an
    # oslo_upgradecheck.upgradecheck.Result
    # object with the appropriate
    # oslo_upgradecheck.upgradecheck.Code and details set.
    # If the check hits warnings or failures then those should be stored
    # in the returned Result's "details" attribute. The
    # summary will be rolled up at the end of the check() method.
    _upgrade_checks = (
        # Added in Victoria
        (_('Policy File JSON to YAML Migration'), _check_policy_json),
    )


def main():
    return upgradecheck.main(
        cfg.CONF, project='cyborg', upgrade_command=Checks())


if __name__ == '__main__':
    sys.exit(main())
