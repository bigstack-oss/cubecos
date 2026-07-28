# Cube SDK
# cyborg installation

CYBORG_CONF_DIR := /etc/cyborg
CYBORG_LOG_DIR := /var/log/cyborg
CYBORG_APP_DIR := /var/lib/cyborg
CYBORG_RUN_DIR := /var/run/cyborg

CYBORG_SRCDIR := $(ROOTDIR)/opt/openstack-antelope/lib/python3.10/site-packages/cyborg
CYBORG_PATCHDIR := $(COREDIR)/cyborg/$(NEXT_OPENSTACK_RELEASE)_patch

# cyborg
CYBORG_REPO_URL := https://github.com/openstack/cyborg.git

# cyborg command line plugin
CYBORG_CLI_REPO_URL := https://github.com/openstack/python-cyborgclient.git

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/cyborg
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/cyborg

# install cyborg inside the python 3.10 virtual environment
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(NEXT_OPS_GITHUB_BRANCH_02) --depth 1 $(CYBORG_REPO_URL) /tmp/cyborg/cyborg
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		-r /tmp/cyborg/cyborg/requirements.txt
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/cyborg/cyborg && \
		/opt/openstack-antelope/bin/python setup.py install"
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(NEXT_OPS_GITHUB_BRANCH_02) --depth 1 $(CYBORG_CLI_REPO_URL) /tmp/cyborg/python-cyborgclient
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		-r /tmp/cyborg/python-cyborgclient/requirements.txt
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/cyborg/python-cyborgclient && \
		/opt/openstack-antelope/bin/python setup.py install"
	$(Q)# The osc plugin has to live in the system python as well: /usr/bin/openstack
	$(Q)# runs under python3.9 and only sees entry points installed there, so a
	$(Q)# venv-only client silently drops the "openstack accelerator ..." commands.
	$(Q)# Remove once python-openstackclient itself moves into the venv.
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/cyborg/python-cyborgclient && \
		/usr/bin/python3 setup.py install"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cyborg /usr/bin/cyborg
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cyborg-agent /usr/bin/cyborg-agent
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cyborg-api /usr/bin/cyborg-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cyborg-conductor /usr/bin/cyborg-conductor
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cyborg-dbsync /usr/bin/cyborg-dbsync
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cyborg-status /usr/bin/cyborg-status
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cyborg-wsgi-api /usr/bin/cyborg-wsgi-api

rootfs_install::
	$(Q)[ -d $(CYBORG_PATCHDIR) ] && cp -rf $(CYBORG_PATCHDIR)/* $(CYBORG_SRCDIR)/ || /bin/true

# cyborg user/group/directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(CYBORG_CONF_DIR) $(CYBORG_APP_DIR) $(CYBORG_LOG_DIR) $(CYBORG_RUN_DIR)
	$(Q)chroot $(ROOTDIR) chown cyborg:cyborg $(CYBORG_CONF_DIR) $(CYBORG_APP_DIR) $(CYBORG_LOG_DIR) $(CYBORG_RUN_DIR)

rootfs_install::
	$(Q)chroot $(ROOTDIR) cp -f /tmp/cyborg/cyborg/etc/cyborg/api-paste.ini $(CYBORG_CONF_DIR)/api-paste.ini
	$(Q)chroot $(ROOTDIR) cp -f /tmp/cyborg/cyborg/etc/cyborg/policy.yaml $(CYBORG_CONF_DIR)/policy.json
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg_sudoers ./etc/sudoers.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg.conf.def .$(CYBORG_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg-conductor.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg-agent.service ./lib/systemd/system

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/cyborg
