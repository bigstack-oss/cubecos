# Cube SDK
# senlin installation

SENLIN_CONF_DIR := /etc/senlin
SENLIN_APP_DIR := /var/lib/senlin
SENLIN_LOG_DIR := /var/log/senlin

ROOTFS_DNF_NOARCH += openstack-senlin-api openstack-senlin-engine

# https://releases.openstack.org/teams/senlin.html
ROOTFS_PIP_DL_FROM_BRANCH_YOGA_UNMAINTAINED += https://github.com/openstack/senlin-dashboard.git

rootfs_install::
	$(Q)cp -f $(PIPS_DIR)/senlin-dashboard.git/senlin_dashboard/enabled/_50_senlin.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(SENLIN_CONF_DIR) $(SENLIN_APP_DIR) $(SENLIN_LOG_DIR)
	$(Q)chroot $(ROOTDIR) chown senlin:senlin $(SENLIN_CONF_DIR) $(SENLIN_APP_DIR) $(SENLIN_LOG_DIR)
	$(Q)cp -f $(ROOTDIR)/$(SENLIN_CONF_DIR)/senlin.conf $(ROOTDIR)/$(SENLIN_CONF_DIR)/senlin.conf.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/senlin/senlin-conductor ./usr/bin
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/senlin/senlin-health-manager ./usr/bin
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/senlin/openstack-senlin-conductor.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/senlin/openstack-senlin-health-manager.service ./lib/systemd/system
	$(Q)chroot $(ROOTDIR) chmod 755 /usr/bin/senlin-conductor /usr/bin/senlin-health-manager