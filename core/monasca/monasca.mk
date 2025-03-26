# Cube SDK
# monasca installation

MONASCA_CONF_DIR := /etc/monasca
MONASCA_APP_DIR := /var/lib/monasca
MONASCA_LOG_DIR := /var/log/monasca
MONASCA_RUN_DIR := /var/run/monasca

MONASCA_SRCDIR := $(ROOTDIR)/usr/local/lib/python3.9/site-packages
MONASCA_PATCHDIR := $(COREDIR)/monasca/$(OPENSTACK_RELEASE)_patch


# config file examples are copied from github repo: openstack-ansible-os_monasca
# monasca common
ROOTFS_PIP_DL_FROM_BRANCH_YOGA_UNMAINTAINED += https://github.com/openstack/monasca-common.git

# monasca command line plugin
ROOTFS_PIP_DL_FROM_TAG_YOGA += https://github.com/openstack/python-monascaclient.git

# monasca-persister
ROOTFS_PIP_DL_FROM_TAG_YOGA += https://github.com/openstack/monasca-persister.git


# monasca user/group/directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(MONASCA_CONF_DIR) $(MONASCA_APP_DIR) $(MONASCA_LOG_DIR) $(MONASCA_RUN_DIR)
	$(Q)chroot $(ROOTDIR) chown monasca:monasca $(MONASCA_CONF_DIR) $(MONASCA_APP_DIR) $(MONASCA_LOG_DIR) $(MONASCA_RUN_DIR)

rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -f $(MONASCA_CONF_DIR)/persister-logging.conf
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/persister/persister-logging.conf .$(MONASCA_CONF_DIR)
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/monasca/persister/persister.conf .$(MONASCA_CONF_DIR)/persister.conf.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/persister/monasca-persister.service ./lib/systemd/system

# monasca-api
ROOTFS_PIP_DL_FROM_TAG_YOGA += https://github.com/openstack/monasca-api.git

rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -f $(MONASCA_CONF_DIR)/api-config.ini $(MONASCA_CONF_DIR)/api-logging.conf
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/api/api-config.ini .$(MONASCA_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/api/api-logging.conf .$(MONASCA_CONF_DIR)
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/monasca/api/api-config.conf .$(MONASCA_CONF_DIR)/api-config.conf.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/api/monasca-mysql.sql .$(MONASCA_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/api/monasca-api-wsgi.conf.in ./etc/httpd/conf.d/


ROOTFS_PIP_DL_FROM_TAG_YOGA += https://github.com/openstack/monasca-agent.git

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(MONASCA_CONF_DIR)/agent/conf.d.in
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/monasca-collector.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/monasca-forwarder.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/agent.yaml.in .$(MONASCA_CONF_DIR)/agent
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/conf.d.in/haproxy.yaml.in .$(MONASCA_CONF_DIR)/agent/conf.d.in
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/conf.d.in/libvirt.yaml.in .$(MONASCA_CONF_DIR)/agent/conf.d.in
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/conf.d.in/mcache.yaml.in .$(MONASCA_CONF_DIR)/agent/conf.d.in
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/conf.d.in/http_check.yaml.in .$(MONASCA_CONF_DIR)/agent/conf.d.in
	$(Q)chroot $(ROOTDIR) chmod 644 $(MONASCA_CONF_DIR)/agent/conf.d.in

rootfs_install::
	$(Q)[ -d $(MONASCA_PATCHDIR) ] && cp -rf $(MONASCA_PATCHDIR)/* $(MONASCA_SRCDIR)/ || /bin/true
