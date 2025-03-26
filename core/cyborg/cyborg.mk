# Cube SDK
# cyborg installation

CYBORG_CONF_DIR := /etc/cyborg
CYBORG_LOG_DIR := /var/log/cyborg
CYBORG_APP_DIR := /var/lib/cyborg
CYBORG_RUN_DIR := /var/run/cyborg

CYBORG_SRCDIR := $(ROOTDIR)/usr/local/lib/python3.9/site-packages/cyborg
CYBORG_PATCHDIR := $(COREDIR)/cyborg/$(OPENSTACK_RELEASE)_patch

# cyborg
ROOTFS_PIP_DL_FROM += https://github.com/openstack/cyborg.git

# cyborg command line plugin
ROOTFS_PIP_DL_FROM += https://github.com/openstack/python-cyborgclient.git

rootfs_install::
	$(Q)[ -d $(CYBORG_PATCHDIR) ] && cp -rf $(CYBORG_PATCHDIR)/* $(CYBORG_SRCDIR)/ || /bin/true

# cyborg user/group/directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(CYBORG_CONF_DIR) $(CYBORG_APP_DIR) $(CYBORG_LOG_DIR) $(CYBORG_RUN_DIR)
	$(Q)chroot $(ROOTDIR) chown cyborg:cyborg $(CYBORG_CONF_DIR) $(CYBORG_APP_DIR) $(CYBORG_LOG_DIR) $(CYBORG_RUN_DIR)

rootfs_install::
	$(Q)cp -f $(PIPS_DIR)/cyborg.git/etc/cyborg/api-paste.ini $(ROOTDIR)/$(CYBORG_CONF_DIR)/api-paste.ini
	$(Q)cp -f $(PIPS_DIR)/cyborg.git/etc/cyborg/policy.yaml $(ROOTDIR)/$(CYBORG_CONF_DIR)/policy.json
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg_sudoers ./etc/sudoers.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg.conf.def .$(CYBORG_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg-conductor.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg-agent.service ./lib/systemd/system

rootfs_install::
	$(Q)[ -d $(CYBORG_PATCHDIR) ] && cp -rf $(CYBORG_PATCHDIR)/* $(CYBORG_SRCDIR)/ || /bin/true