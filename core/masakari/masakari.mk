# Cube SDK
# masakari installation

MASAKARI_CONF_DIR := /etc/masakari
MASAKARI_MONITORS_CONF_DIR := /etc/masakarimonitors
MASAKARI_APP_DIR := /var/lib/masakari
MASAKARI_LOG_DIR := /var/log/masakari
MASAKARI_RUN_DIR := /var/run/masakari

MASAKARI_SRCDIR := $(ROOTDIR)/usr/local/lib/python3.9/site-packages
MASAKARI_PATCHDIR := $(COREDIR)/masakari/$(OPENSTACK_RELEASE)_patch

# masakari common
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(MASAKARI_CONF_DIR) $(MASAKARI_MONITORS_CONF_DIR) $(MASAKARI_APP_DIR) $(MASAKARI_LOG_DIR) $(MASAKARI_RUN_DIR)
	$(Q)chroot $(ROOTDIR) chown masakari:masakari $(MASAKARI_CONF_DIR) $(MASAKARI_MONITORS_CONF_DIR) $(MASAKARI_APP_DIR) $(MASAKARI_LOG_DIR) $(MASAKARI_RUN_DIR)


# masakari-api and masakari-engine
ROOTFS_PIP_DL_FROM += https://github.com/openstack/masakari.git

rootfs_install::
	$(Q)cp -f $(PIPS_DIR)/masakari.git/etc/masakari/api-paste.ini $(ROOTDIR)$(MASAKARI_CONF_DIR)/api-paste.ini
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari.conf.def .$(MASAKARI_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari_sudoers ./etc/sudoers.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-engine.service ./lib/systemd/system


# masakari-monitors process/instance/host
ROOTFS_PIP_DL_FROM += https://github.com/openstack/masakari-monitors.git

rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakarimonitors.conf.def $(MASAKARI_MONITORS_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/process_list.yaml $(MASAKARI_MONITORS_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-instancemonitor.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-processmonitor.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-hostmonitor.service ./lib/systemd/system


# masakari command line plugin
ROOTFS_PIP_DL_FROM += https://github.com/openstack/python-masakariclient.git

# masakari web ui plugin
ROOTFS_PIP_DL_FROM += https://github.com/openstack/masakari-dashboard.git

rootfs_install::
	$(Q)cp -f $(PIPS_DIR)/masakari-dashboard.git/masakaridashboard/local/enabled/_50_masakaridashboard.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled
	$(Q)cp -f $(PIPS_DIR)/masakari-dashboard.git/masakaridashboard/local/local_settings.d/_50_masakari.py $(ROOTDIR)/$(HORIZON_DIR)/local/local_settings.d
	$(Q)chroot $(ROOTDIR) python3 /usr/share/openstack-dashboard/manage.py dump_default_policies --namespace masakari --output-file $(HORIZON_POLICY_DIR)/masakari.yaml 2>&1 > /dev/null

rootfs_install::
	$(Q)[ -d $(MASAKARI_PATCHDIR) ] && cp -rf $(MASAKARI_PATCHDIR)/* $(MASAKARI_SRCDIR)/ || /bin/true
