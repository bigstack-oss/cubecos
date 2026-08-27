# Cube SDK
# cyborg installation

CYBORG_CONF_DIR := /etc/cyborg
CYBORG_LOG_DIR := /var/log/cyborg
CYBORG_APP_DIR := /var/lib/cyborg
CYBORG_RUN_DIR := /var/run/cyborg

# https://releases.openstack.org/teams/cyborg.html
# The service is a pinned pip install; nothing here is built from git any more,
# so there is no checkout to patch and $(CYBORG_SRCDIR) is the installed package.
CYBORG_SRCDIR := $(ROOTDIR)$(CARACAL_OPENSTACK_HOME_DIR)/lib/python$(CARACAL_PYTHON_VER)/site-packages/cyborg
CYBORG_PATCHDIR := $(COREDIR)/cyborg/$(CARACAL_OPENSTACK_RELEASE)_patch

# install cyborg into the caracal venv
#
# 12.0.0 is the 2024.1 release. The service moves into
# $(CARACAL_OPENSTACK_HOME_DIR) with keystone, glance, cinder, nova/placement,
# neutron, manila and octavia.
#
# This also converts the install from `git clone` + `setup.py install` to a
# pinned pip install, which is what every caracal hop before it does -- there is
# no .mk in this tree that still reads $(CARACAL_OPS_GITHUB_BRANCH_0*), and
# stable/2024.1 does not exist on the github mirror anyway.
#
# The distribution is openstack-cyborg, not cyborg. `cyborg` on PyPI is an
# unrelated project that stops at 0.2, so the obvious spelling cannot resolve
# 12.0.0 at all -- and if it ever gains that version it would install something
# else entirely.
#
# Two packages have to be named because cyborg's requirements.txt asks for
# neither and pip will not pull them in transitively:
# PyMySQL: config_cyborg.cpp writes a mysql+pymysql:// connection
# oslo.messaging[kafka]: config_cyborg.cpp points the notification transport at
#   kafka://
# Both happen to be in this venv already (keystone.mk installs them), but a
# dependency nothing asks for is one that disappears silently.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(CARACAL_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		openstack-cyborg==12.0.0 \
		PyMySQL \
		\"oslo.messaging[kafka]\""
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/cyborg-agent /usr/bin/cyborg-agent
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/cyborg-api /usr/bin/cyborg-api
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/cyborg-conductor /usr/bin/cyborg-conductor
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/cyborg-dbsync /usr/bin/cyborg-dbsync
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/cyborg-status /usr/bin/cyborg-status
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/cyborg-wsgi-api /usr/bin/cyborg-wsgi-api

# the osc plugin stays in the antelope venv -- TEMPORARY
#
# python-cyborgclient owns the `openstack accelerator ...` commands, and a
# stevedore entry point is only visible to the interpreter it was installed
# under. /usr/bin/openstack is the antelope venv's (core/heavyfs/Makefile), so
# the plugin has to stay next to it or those commands disappear from the cli.
# Every service whose client owns an osc plugin meets this on its way over.
#
# Nothing in hex_sdk drives this one -- health_cyborg_check() only asks systemd
# whether the three units are running -- so no health check depends on it. What
# would go quiet is the operator-facing cli.
#
# It is a pip install rather than a git checkout for the same reason the service
# is, and no version is named: os-antelope-pip-upper-constraints.txt already
# carries python-cyborgclient (2.1.0), so a version here could only drift from
# that file.
#
# It goes once /usr/bin/openstack is the caracal venv's (#636).
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-cyborgclient
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link the cli plugin's console script, which is the antelope venv's
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/cyborg /usr/bin/cyborg

rootfs_install::
	$(Q)[ -d $(CYBORG_PATCHDIR) ] && cp -rf $(CYBORG_PATCHDIR)/* $(CYBORG_SRCDIR)/ || /bin/true

# cyborg user/group/directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(CYBORG_CONF_DIR) $(CYBORG_APP_DIR) $(CYBORG_LOG_DIR) $(CYBORG_RUN_DIR)
	$(Q)chroot $(ROOTDIR) chown cyborg:cyborg $(CYBORG_CONF_DIR) $(CYBORG_APP_DIR) $(CYBORG_LOG_DIR) $(CYBORG_RUN_DIR)

rootfs_install::
	$(Q)# api-paste.ini and the policy file come out of the venv prefix rather
	$(Q)# than a git checkout: cyborg's setup.cfg data_files puts both there, and
	$(Q)# taking them from the install means they track the pinned version instead
	$(Q)# of going stale silently. cinder.mk, glance.mk and manila.mk do the same.
	$(Q)#
	$(Q)# The policy file keeps upstream's name. cyborg sets its own default for
	$(Q)# CONF.oslo_policy.policy_file to policy.yaml (cyborg/common/authorize_wsgi.py)
	$(Q)# and only falls back to policy.json when no policy.yaml is found -- a
	$(Q)# compatibility path its own TODO says will be removed. Installing it as
	$(Q)# policy.json, as this did, worked solely through that fallback.
	$(Q)chroot $(ROOTDIR) cp -f $(CARACAL_OPENSTACK_HOME_DIR)/etc/cyborg/api-paste.ini $(CYBORG_CONF_DIR)/api-paste.ini
	$(Q)chroot $(ROOTDIR) cp -f $(CARACAL_OPENSTACK_HOME_DIR)/etc/cyborg/policy.yaml $(CYBORG_CONF_DIR)/policy.yaml
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg_sudoers ./etc/sudoers.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg.conf.def .$(CYBORG_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg-conductor.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg-agent.service ./lib/systemd/system
