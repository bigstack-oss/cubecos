# Copyright (c) 2015 Red Hat, Inc.
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
import os
import os.path

from neutron.agent.linux import ip_lib

from neutron_vpnaas.services.vpn.device_drivers import ipsec


class LibreSwanProcess(ipsec.OpenSwanProcess):
    """Libreswan Process manager class.

    Libreswan needs nssdb initialised before running pluto daemon.
    """
    # pylint: disable=useless-super-delegation
    def __init__(self, conf, process_id, vpnservice, namespace):
        self._rootwrap_cfg = self._get_rootwrap_config()
        super(LibreSwanProcess, self).__init__(conf, process_id,
                                              vpnservice, namespace)

    def _ipsec_execute(self, cmd, check_exit_code=True, extra_ok_codes=None):
        """Execute ipsec command on namespace.

        This execute is wrapped by namespace wrapper.
        The namespace wrapper will bind /etc and /var/run
        """
        ip_wrapper = ip_lib.IPWrapper(namespace=self.namespace)
        mount_paths = {'/etc': '%s/etc' % self.config_dir,
                       '/var/run': '%s/var/run' % self.config_dir}
        mount_paths_str = ','.join(
            "%s:%s" % (source, target)
            for source, target in mount_paths.items())
        ns_wrapper = self.get_ns_wrapper()
        return ip_wrapper.netns.execute(
            [ns_wrapper,
             '--mount_paths=%s' % mount_paths_str,
             ('--rootwrap_config=%s' % self._rootwrap_cfg
                 if self._rootwrap_cfg else ''),
             '--cmd=%s,%s' % (self.binary, ','.join(cmd))],
            check_exit_code=check_exit_code,
            extra_ok_codes=extra_ok_codes)

    def _ensure_needed_files(self):
        # addconn reads from /etc/hosts and /etc/resolv.conf. As /etc would be
        # bind-mounted, create these two empty files in the target directory.
        with open('%s/etc/hosts' % self.config_dir, 'a'):
            pass
        with open('%s/etc/resolv.conf' % self.config_dir, 'a'):
            pass

    def ensure_configs(self):
        """Generate config files which are needed for Libreswan.

        Initialise the nssdb, otherwise pluto daemon will fail to run.
        """

        # Since we set ipsec.secrets to be owned by root, the standard
        # mechanisms for setting up the config files will get a permission
        # problem when attempting to overwrite the file, so we need to
        # remove it first.
        secrets_file = self._get_config_filename('ipsec.secrets')
        if os.path.exists(secrets_file):
            self._execute(['rm', '-f', secrets_file])

        super(LibreSwanProcess, self).ensure_configs()

        # LibreSwan uses the capabilities library to restrict access to
        # ipsec.secrets to users that have explicit access. Since pluto is
        # running as root and the file has 0600 perms, we must set the
        # owner of the file to root.
        self._execute(['chown', '--from=%s' % os.getuid(), 'root:root',
                       secrets_file])

        # Libreswan needs to write logs to this directory.
        self._execute(['chown', '--from=%s' % os.getuid(), 'root:root',
                       self.log_dir])

        self._ensure_needed_files()

        # Load the ipsec kernel module if not loaded
        self._ipsec_execute(['_stackmanager', 'start'])
        # checknss creates nssdb only if it is missing
        # It is added in Libreswan version v3.10
        # For prior versions use initnss
        try:
            self._ipsec_execute(['checknss'])
        except RuntimeError:
            self._ipsec_execute(['initnss'])

    def get_status(self):
        return self._ipsec_execute(['whack', '--status'],
                                   extra_ok_codes=[1, 3])

    def start_pluto(self):
        cmd = ['pluto',
               '--use-netkey',
               '--uniqueids']

        if self.conf.ipsec.enable_detailed_logging:
            cmd += ['--perpeerlog', '--perpeerlogbase', self.log_dir]
        self._ipsec_execute(cmd)

    def add_ipsec_connection(self, nexthop, conn_id):
        # Connections will be automatically added as auto=start/add for
        # initiator=bi-directional/response-only specified in the config.
        pass

    def start_whack_listening(self):
        # NOTE(huntxu): This is a workaround for with a weak (len<8) secret,
        # "ipsec whack --listen" will exit with 3.
        self._ipsec_execute(['whack', '--listen'], extra_ok_codes=[3])

    def shutdown_whack(self):
        self._ipsec_execute(['whack', '--shutdown'])

    def initiate_connection(self, conn_name):
        self._ipsec_execute(
            ['whack', '--name', conn_name, '--asynchronous', '--initiate'])

    def terminate_connection(self, conn_name):
        self._ipsec_execute(['whack', '--name', conn_name, '--terminate'])


class LibreSwanDriver(ipsec.IPsecDriver):
    def create_process(self, process_id, vpnservice, namespace):
        return LibreSwanProcess(
            self.conf,
            process_id,
            vpnservice,
            namespace)
