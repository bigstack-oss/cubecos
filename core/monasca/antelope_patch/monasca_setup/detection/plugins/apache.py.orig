# (C) Copyright 2015,2016 Hewlett Packard Enterprise Development Company LP
# (C) Copyright 2018 SUSE LLC

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

import logging
import os
import urllib

import monasca_setup.agent_config
import monasca_setup.detection

log = logging.getLogger(__name__)

# Process name is apache2 on Debian derivatives, on RHEL derivatives it's httpd,
# on openSUSE/SLES it might be httpd-prefork or httpd-worker. With some versions
# of apache2-mod_perl, e.g., 2.0.8, the process name is "/usr/sbin/httpd" after
# being truncated to the UNIX limit of 15 characters. "/usr/sbin/httpd" should
# be removed from the list when we conclude the offending verson(s) of the
# mod_perl is no longer in use.
APACHE_PROCESS_NAMES = ('apache2', 'httpd', 'httpd-prefork', 'httpd-worker', '/usr/sbin/httpd')
DEFAULT_APACHE_CONFIG = '/root/.apache.cnf'
CONFIG_ARG_KEYS = set(["url", "user", "password", "use_server_status_metrics"])


class Apache(monasca_setup.detection.Plugin):
    """Detect Apache web server daemons and setup configuration to monitor apache.

        This plugin will by default setup process check metrics for the apache process,
        and setup server-status metrics using the input url.  If only process check
        metrics are desired, the use_server_status_metrics argument can be passed in
        with a value of false.
        This plugin needs user/password for apache if using the server-status metrics
        when security is setup on the web server.
        This plugin accepts arguments and if none are provided it will attempt to read
        the default configuration file (/root/.apache.cnf) in a format such as:
        [client]
            url=http://localhost/server-status?auto
            user=guest
            password=guest
    """

    def __init__(self, *args, **kwargs):
        self._apache_process_name = 'apache2'
        super(Apache, self).__init__(*args, **kwargs)

    def _detect(self):
        """Run detection, set self.available True if the service is detected.

        """
        process_exists = False
        for proc_name in APACHE_PROCESS_NAMES:
            if monasca_setup.detection.find_process_name(proc_name) is not None:
                self._apache_process_name = proc_name
                process_exists = True
        has_args_or_config_file = (self.args is not None or
                                   os.path.isfile(DEFAULT_APACHE_CONFIG))
        self.available = process_exists and has_args_or_config_file
        if not self.available:
            if not process_exists:
                log.info('Apache process does not exist.')
            elif not has_args_or_config_file:
                log.warning(('Apache process exists but '
                             'configuration file was not found and '
                             'no arguments were given.'))

    def _read_apache_config(self, config_location):
        # Read the apache config file to extract the needed variables.
        client_section = False
        apache_url = None
        apache_user = None
        apache_pass = None
        use_server_status_metrics = True
        try:
            with open(config_location, "r") as config_file:
                for row in config_file:
                    if "[client]" in row:
                        client_section = True
                        continue
                    if client_section:
                        if "url=" in row:
                            apache_url = row.split("=")[1].strip()
                        if "user=" in row:
                            apache_user = row.split("=")[1].strip()
                        if "password=" in row:
                            apache_pass = row.split("=")[1].strip()
                        if "use_server_status_metrics" in row:
                            use_server_status_metrics = row.split("=")[1].strip()
        except IOError:
            log.warn("\tUnable to read {:s}".format(config_location))

        return apache_url, apache_user, apache_pass, use_server_status_metrics

    def build_config(self):
        """Build the config as a Plugins object and return.

        """
        config = monasca_setup.agent_config.Plugins()
        # First watch the process
        config.merge(monasca_setup.detection.watch_process(
            [self._apache_process_name], 'apache'))
        log.info("\tWatching the apache webserver process.")

        error_msg = '\n\t*** The Apache plugin is not configured ***\n\tPlease correct and re-run'
        'monasca-setup.'
        # Attempt login, requires either an empty root password from localhost
        # or relying on a configured /root/.apache.cnf
        if self.dependencies_installed():
            # If any of the exact keys are present, use them.
            if self.args and self.args.viewkeys() & CONFIG_ARG_KEYS:
                log.info("Attempting to use command args")
                apache_url = self.args.get("url", None)
                apache_user = self.args.get("user", None)
                apache_pass = self.args.get("password", None)
                use_server_status_metrics = self.args.get('use_server_status_metrics', True)
            elif self.args and self.args.get("apache_config_file"):
                config_file = self.args.get("apache_config_file")
                apache_url, apache_user, apache_pass, use_server_status_metrics = \
                    self._read_apache_config(config_file)
            else:
                apache_url, apache_user, apache_pass, use_server_status_metrics = \
                    self._read_apache_config(DEFAULT_APACHE_CONFIG)
            if type(use_server_status_metrics) is str:
                use_server_status_metrics = (use_server_status_metrics.lower() == 'true')

            if use_server_status_metrics:
                if not apache_url:
                    missing_url_msg = ('\tNo server-status url specified.' + error_msg)
                    log.error(missing_url_msg)
                    raise Exception(missing_url_msg)
            else:
                log.info("\tWatching the apache process only.")
                return config

            if apache_user and apache_pass:
                password_mgr = urllib.request.HTTPPasswordMgrWithDefaultRealm()
                password_mgr.add_password(None,
                                          apache_url,
                                          apache_user,
                                          apache_pass)
                handler = urllib.request.HTTPBasicAuthHandler(password_mgr)
            else:
                if 'https' in apache_url:
                    handler = urllib.request.HTTPSHandler()
                else:
                    handler = urllib.request.HTTPHandler()

            opener = urllib.request.build_opener(handler)

            try:
                request = opener.open(apache_url)
                response = request.read()
                request.close()
                if 'Total Accesses:' in response:
                    instance_vars = {'name': apache_url, 'apache_status_url': apache_url}
                    if apache_user and apache_pass:
                        instance_vars.update({'apache_user': apache_user,
                                              'apache_password': apache_pass})
                    config['apache'] = {'init_config': None, 'instances': [instance_vars]}
                    log.info("\tSuccessfully setup Apache plugin.")
                else:
                    log.warn('Unable to access the Apache server-status URL;' + error_msg)
            except urllib.error.URLError as e:
                exception_msg = (
                    '\tError {0} received when accessing url {1}.'.format(e.reason, apache_url) +
                    '\n\tPlease ensure the Apache web server is running and your configuration ' +
                    'information is correct.' + error_msg)
                log.error(exception_msg)
                raise Exception(exception_msg)
            except Exception as e:
                exception_msg = (
                    'Error received when accessing url {0} exception {1}'.format(apache_url, e) +
                    error_msg)
                log.error(exception_msg)
                raise Exception(exception_msg)
        else:
            log.error(
                '\tThe dependencies for Apache Web Server are not installed or unavailable.' +
                error_msg)

        return config

    def dependencies_installed(self):
        # No real dependencies to check
        return True
