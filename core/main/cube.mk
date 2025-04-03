# Core Rootfs

## Install /usr/sbin/hex_sdk modules.pre
hex_shell_MODULES_PRE += $(PROJ_SHMODDIR)/modules.pre/sdk_01-var-static.sh
hex_shell_MODULES_PRE += $(PROJ_SHMODDIR)/modules.pre/sdk_02-var-runtime.sh
hex_shell_MODULES_PRE += $(PROJ_SHMODDIR)/modules.pre/sdk_cmd.sh
hex_shell_MODULES_PRE += $(PROJ_SHMODDIR)/modules.pre/sdk_is.sh
hex_shell_MODULES_PRE += $(PROJ_SHMODDIR)/modules.pre/sdk_license.sh
hex_shell_MODULES_PRE += $(PROJ_SHMODDIR)/modules.pre/sdk_remote.sh
hex_shell_MODULES_PRE += $(PROJ_SHMODDIR)/modules.pre/sdk_stale.sh

## Install /usr/sbin/hex_sdk modules
hex_shell_MODULES += $(HEX_SHMODDIR)/sdk_firmware.sh
hex_shell_MODULES += $(HEX_SHMODDIR)/sdk_snapshot.sh
hex_shell_MODULES += $(HEX_SHMODDIR)/sdk_update.sh
hex_shell_MODULES += $(HEX_SHMODDIR)/sdk_banner.sh
hex_shell_MODULES += $(HEX_SHMODDIR)/sdk_preset.sh
hex_shell_MODULES += $(HEX_SHMODDIR)/sdk_util.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/errcodes
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_alert.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_app.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_banner.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_ceph.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_diagnostics.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_firmware.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_gcp.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_git.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_gpu.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_haproxy.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_health.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_hwdetect.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_k3s.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_kafka.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_api.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_lmi.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_logs.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_memcache.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_migrate.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_mongodb.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_mysql.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_network.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_ntp.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_opensearch.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_os.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_ovn.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_pacemaker.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_preset.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_rabbitmq.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_security.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_snapshot.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_stats.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_support.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_toggle.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_tuning.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_update.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_util.sh
hex_shell_MODULES += $(PROJ_SHMODDIR)/modules/sdk_zookeeper.sh

## Install /usr/sbin/hex_sdk modules.post
hex_shell_MODULES_POST += $(PROJ_SHMODDIR)/modules.post/sdk_99wrapper.sh

## Build/Install hex binaries

hex_firsttime_MODULES += firsttime_welcome.o
hex_firsttime_MODULES += firsttime_sla.o
hex_firsttime_MODULES += firsttime_password.o
hex_firsttime_MODULES += firsttime_hostname.o
hex_firsttime_MODULES += firsttime_net_bonding.o
hex_firsttime_MODULES += firsttime_net_vlan.o
hex_firsttime_MODULES += firsttime_net.o
hex_firsttime_MODULES += firsttime_dns.o
hex_firsttime_MODULES += firsttime_time.o
hex_firsttime_MODULES += firsttime_cubesys.o
hex_firsttime_MODULES += firsttime_cubeha.o

PROGRAMS += hex_firsttime

hex_translate_MODULES += translate_net.o
hex_translate_MODULES += translate_time.o
hex_translate_MODULES += translate_tuning.o
hex_translate_MODULES += translate_cubesys.o
hex_translate_MODULES += translate_keystone.o
hex_translate_MODULES += translate_ntp.o
hex_translate_MODULES += translate_ext_storage.o
hex_translate_MODULES += translate_alert_resp.o
hex_translate_MODULES += translate_rancher.o

PROGRAMS += hex_translate

# HEX modules (order matters)
hex_config_MODULES += config_sys.o
hex_config_MODULES += config_bootstrap.o
hex_config_MODULES += config_password.o
hex_config_MODULES += config_cron.o
hex_config_MODULES += config_debug.o
hex_config_MODULES += config_syslogd.o
hex_config_MODULES += config_net.o
hex_config_MODULES += config_net_static.o
hex_config_MODULES += config_net_dynamic.o
hex_config_MODULES += config_sshd.o
hex_config_MODULES += config_appliance.o
hex_config_MODULES += config_usb.o
hex_config_MODULES += config_iso.o
hex_config_MODULES += config_supportbase.o
hex_config_MODULES += config_support.o
hex_config_MODULES += config_snapshotbase.o
hex_config_MODULES += config_snapshot.o
hex_config_MODULES += config_time.o
hex_config_MODULES += config_fixpack.o
hex_config_MODULES += config_update.o

# CUBE modules
hex_config_LIBS += $(PROJ_LIBDIR)/libcube_sdk.a $(PROJ_LIBDIR)/libmysql_util.a

# cube moudles
hex_config_MODULES += config_cluster.o
hex_config_MODULES += config_docker.o
hex_config_MODULES += config_keycloak.o
hex_config_MODULES += config_rancher.o
hex_config_MODULES += config_cubesys.o
hex_config_MODULES += config_cube_scan.o
hex_config_MODULES += config_rabbitmq.o
hex_config_MODULES += config_mysql.o
hex_config_MODULES += config_ntp.o
hex_config_MODULES += config_memcache.o
hex_config_MODULES += config_libvirtd.o
hex_config_MODULES += config_ceph.o
hex_config_MODULES += config_apache2.o
hex_config_MODULES += config_lmi.o
hex_config_MODULES += config_glance.o
hex_config_MODULES += config_horizon.o
hex_config_MODULES += config_keystone.o
hex_config_MODULES += config_ironic.o
hex_config_MODULES += config_neutron.o
hex_config_MODULES += config_nova.o
hex_config_MODULES += config_cinder.o
hex_config_MODULES += config_swift.o
hex_config_MODULES += config_heat.o
hex_config_MODULES += config_barbican.o
hex_config_MODULES += config_masakari.o
hex_config_MODULES += config_manila.o
hex_config_MODULES += config_monasca.o
hex_config_MODULES += config_octavia.o
hex_config_MODULES += config_designate.o
hex_config_MODULES += config_senlin.o
hex_config_MODULES += config_watcher.o
hex_config_MODULES += config_cyborg.o
hex_config_MODULES += config_api.o
hex_config_MODULES += config_skyline.o
hex_config_MODULES += config_nginx.o
hex_config_MODULES += config_corosync.o
hex_config_MODULES += config_pacemaker.o
hex_config_MODULES += config_haproxy.o
hex_config_MODULES += config_k3s.o
hex_config_MODULES += config_grafana.o
hex_config_MODULES += config_volume_meta.o
hex_config_MODULES += config_influxdb.o
hex_config_MODULES += config_kapacitor.o
hex_config_MODULES += config_telegraf.o
hex_config_MODULES += config_opensearch.o
hex_config_MODULES += config_opensearch_dashboards.o
hex_config_MODULES += config_logstash.o
hex_config_MODULES += config_kafka.o
hex_config_MODULES += config_prometheus.o
hex_config_MODULES += config_mongodb.o

PROGRAMS += hex_config

hex_cli_MODULES += cli_cubesys.o
hex_cli_MODULES += cli_ssh.o
hex_cli_MODULES += cli_appliance.o
hex_cli_MODULES += cli_support.o
hex_cli_MODULES += cli_snapshot.o
hex_cli_MODULES += cli_netutil.o
hex_cli_MODULES += cli_fixpack.o
hex_cli_MODULES += cli_update.o
hex_cli_MODULES += cli_tuning.o
hex_cli_MODULES += cli_firmware.o
hex_cli_MODULES += cli_ntp.o
hex_cli_MODULES += cli_ceph.o
hex_cli_MODULES += cli_iaas_network.o
hex_cli_MODULES += cli_iaas_compute.o
hex_cli_MODULES += cli_iaas_volume.o
hex_cli_MODULES += cli_volume_meta.o
hex_cli_MODULES += cli_image.o
hex_cli_MODULES += cli_boot.o
hex_cli_MODULES += cli_boot_mode.o
hex_cli_MODULES += cli_cluster.o
hex_cli_MODULES += cli_ext_storage.o
hex_cli_MODULES += cli_alert_resp.o
hex_cli_MODULES += cli_s3.o
hex_cli_MODULES += cli_gpu.o
hex_cli_MODULES += cli_license.o
hex_cli_MODULES += cli_link.o
hex_cli_MODULES += cli_preset.o
hex_cli_MODULES += cli_diagnostics.o
hex_cli_MODULES += cli_autoscaler.o
hex_cli_MODULES += cli_app.o
hex_cli_MODULES += cli_k3s.o

hex_cli_LIBS += $(PROJ_LIBDIR)/libcube_sdk.a

PROGRAMS += hex_cli

hex_crashd_SRCS = $(HEX_TOPDIR)/src/hex_crashd/crash_main.c
hex_crashd_LIBS = $(HEX_SDK_LIB)
hex_crashd_LDLIBS = $(HEX_SDK_LDLIBS)
PROGRAMS += hex_crashd

# Install hex command post scripts
$(call PROJ_INSTALL_SCRIPT,,$(SRCDIR)/post-scripts/hex_translate/translate.post.sh,./etc/hex_translate/post.d/)
$(call PROJ_INSTALL_SCRIPT,,$(SRCDIR)/post-scripts/hex_config/apply.post.sh,./etc/hex_config/post.d/)
$(call PROJ_INSTALL_SCRIPT,,$(SRCDIR)/post-scripts/hex_config/bootstrap.post.sh,./etc/hex_config/post.d/)

# Add policies
# Factory default policy dir and settings snapshot will be created during install
POLICY_DEPS := $(shell find $(CORE_POLICYDIR) -type f 2>/dev/null)

$(PROJ_ROOTFS): $(POLICY_DEPS)

# cube sdk
rootfs_install::
	$(Q)echo -n "BOOTSTRAP_MODULE=sys-standalone" > $(ROOTDIR)/etc/bootstrap.cfg
	$(Q)$(INSTALL_SCRIPT) -f $(ROOTDIR) $(COREDIR)/main/proj_functions ./usr/lib/hex_sdk/proj_functions

# cube policy
rootfs_install::
	$(Q)mkdir -p $(ROOTDIR)/etc/policies
	$(Q)cp -r  $(CORE_POLICYDIR)/* $(ROOTDIR)/etc/policies
	# Force the file permissions to be the same (rw-r--r--)
	# Only root should need to update these files
	$(Q)find $(ROOTDIR)/etc/policies -name "*.yml" -exec chmod 644 {} \;

# cube deterministic ssh key generation utility
$(call PROJ_INSTALL_PROGRAM,,$(CORE_PKGDIR)/x86_64/oss/ssh-keydgen,./usr/sbin)

# should not include any dnf package install scripts here
