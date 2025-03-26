# Cube SDK
# designate installation

NAMED_CONF_FILES := /etc/named*
NAMED_APP_DIR := /var/named

DESIGNATE_CONF_DIR := /etc/designate
DESIGNATE_APP_DIR := /var/lib/designate
DESIGNAT_LOG_DIR := /var/log/designate

ROOTFS_DNF += bind bind-utils

DESIGNATE_BINDIR := $(ROOTDIR)/usr/local/bin
DESIGNATE_BIN_PATCHDIR := $(COREDIR)/designate/$(OPENSTACK_RELEASE)_bin_patch

rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/named/named.conf.in ./etc/
	$(Q)chroot $(ROOTDIR) sh -c "chown named:named $(NAMED_CONF_FILES) $(NAMED_APP_DIR)"

# https://releases.openstack.org/teams/designate.html
ROOTFS_PIP_DL_FROM_BRANCH_YOGA_UNMAINTAINED += https://github.com/openstack/designate.git
ROOTFS_PIP_DL_FROM_BRANCH_YOGA_UNMAINTAINED += https://github.com/openstack/python-designateclient.git
ROOTFS_PIP_DL_FROM_TAG_YOGA += https://github.com/openstack/designate-dashboard.git

rootfs_install::
	$(Q)cp -f $(PIPS_DIR)/designate-dashboard.git/designatedashboard/enabled/_17*.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(DESIGNATE_CONF_DIR) $(DESIGNATE_APP_DIR) $(DESIGNAT_LOG_DIR)
	$(Q)chroot $(ROOTDIR) chown designate:designate $(DESIGNATE_CONF_DIR) $(DESIGNATE_APP_DIR) $(DESIGNAT_LOG_DIR)
	$(Q)cp -f $(PIPS_DIR)/designate.git/etc/designate/policy.yaml.sample $(ROOTDIR)$(DESIGNATE_CONF_DIR)/policy.yaml
	$(Q)cp -f $(PIPS_DIR)/designate.git/etc/designate/api-paste.ini $(ROOTDIR)$(DESIGNATE_CONF_DIR)/api-paste.ini
	$(Q)cp -f $(PIPS_DIR)/designate.git/etc/designate/rootwrap.conf.sample $(ROOTDIR)$(DESIGNATE_CONF_DIR)/rootwrap.conf
	$(Q)cp -rf $(PIPS_DIR)/designate.git/etc/designate/rootwrap.d $(ROOTDIR)$(DESIGNATE_CONF_DIR)/
	$(Q)chroot $(ROOTDIR) ln -sf /usr/local/bin/designate-rootwrap /usr/bin/designate-rootwrap
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate.conf.sample .$(DESIGNATE_CONF_DIR)/designate.conf.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate_sudoers ./etc/sudoers.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-agent.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-central.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-worker.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-producer.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-mdns.service ./lib/systemd/system

rootfs_install::
	$(Q)[ -d $(DESIGNATE_BIN_PATCHDIR) ] && cp -rf $(DESIGNATE_BIN_PATCHDIR)/* $(DESIGNATE_BINDIR)/ || /bin/true

