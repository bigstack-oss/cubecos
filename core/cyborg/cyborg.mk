# Cube SDK
# cyborg installation

CYBORG_CONF_DIR := /etc/cyborg
CYBORG_LOG_DIR := /var/log/cyborg
CYBORG_APP_DIR := /var/lib/cyborg
CYBORG_RUN_DIR := /var/run/cyborg

# https://releases.openstack.org/teams/cyborg.html
# The service is a pinned pip install; nothing here is built from git any more,
# so there is no checkout to patch and $(CYBORG_SRCDIR) is the installed package.
CYBORG_SRCDIR := $(ROOTDIR)$(NEXT_OPENSTACK_HOME_DIR)/lib/python$(NEXT_PYTHON_VER)/site-packages/cyborg
CYBORG_PATCHDIR := $(COREDIR)/cyborg/$(NEXT_OPENSTACK_RELEASE)_patch

# install cyborg into the epoxy venv
#
# cyborg runs out of the epoxy venv, not the caracal one it shares with every other
# 2024.1 service. 14.1.0 is the newest 2025.1 release: 14.0.0 was the cycle's, and
# 14.1.0 adds upstream's SQLAlchemy 2.0 session refactor and the fixes for
# CVE-2026-40213 and CVE-2026-40214 on stable/2025.1. It cannot be bumped in place:
# 14.x requires oslo.policy>=4.5.0, which os-caracal-pip-upper-constraints.txt holds
# at 4.3.0 for octavia, heat, manila and the other 2024.1 services still in the
# caracal venv. So the service moves alone into $(NEXT_OPENSTACK_HOME_DIR), the same
# shape as its caracal hop (#633), one release on, after keystone, glance, cinder,
# nova/placement, neutron and barbican.
#
# The distribution is openstack-cyborg, not cyborg. `cyborg` on PyPI is an
# unrelated project that stops at 0.2, so the obvious spelling cannot resolve
# 14.1.0 at all -- and if it ever gains that version it would install something
# else entirely.
#
# Three packages have to be named because cyborg's requirements.txt asks for
# none of them and pip will not pull them in transitively:
# PyMySQL: config_cyborg.cpp writes a mysql+pymysql:// connection
# oslo.messaging[kafka]: config_cyborg.cpp points the notification transport at
#   kafka://
# python-memcached: config_cyborg.cpp writes [keystone_authtoken] memcached_servers,
#   which makes keystonemiddleware import memcache on its first token validation
# All three happen to be in this venv already, but a dependency nothing asks for is
# one that disappears silently.
#
# The /usr/bin/cyborg-* links follow the service: the three units,
# config_cyborg.cpp and hex_sdk's migrate_cyborg_db all reach cyborg through them.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(NEXT_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		openstack-cyborg==14.1.0 \
		PyMySQL \
		\"oslo.messaging[kafka]\" \
		python-memcached"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cyborg-agent /usr/bin/cyborg-agent
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cyborg-api /usr/bin/cyborg-api
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cyborg-conductor /usr/bin/cyborg-conductor
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cyborg-dbsync /usr/bin/cyborg-dbsync
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cyborg-status /usr/bin/cyborg-status
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cyborg-wsgi-api /usr/bin/cyborg-wsgi-api

# the osc plugin
#
# python-cyborgclient owns the `openstack accelerator ...` commands, and a
# stevedore entry point is only visible to the interpreter it was installed
# under, so the plugin has to sit next to /usr/bin/openstack or those commands
# disappear from the cli. That held it in the antelope venv while the cli was
# there, and #636 moved the cli so it sat with the service again. The epoxy hop
# opens the split once more: /usr/bin/openstack is still the caracal venv's, so
# the client stays here until the cli moves too, the same as barbican's (#658).
# Every service whose client owns an osc plugin meets this on its way over.
#
# Nothing in hex_sdk drives it as a health check -- health_cyborg_check() only
# asks systemd whether the three units are running -- so what would go quiet is
# the operator-facing cli, and with it the `openstack accelerator ...` calls in
# sdk_os.sh's gpu device-profile helpers and health_cyborg_report.
#
# It is a pip install rather than a git checkout for the same reason the service
# is, and no version is named: os-caracal-pip-upper-constraints.txt already
# carries python-cyborgclient, so a version here could only drift from that file.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-cyborgclient
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link the cli plugin's console script
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
	$(Q)# The policy file keeps upstream's name, policy.yaml, which is also
	$(Q)# oslo.policy's own default for CONF.oslo_policy.policy_file. 14.x removed
	$(Q)# the policy.json fallback 12.0.0 still carried, so a policy.json would not
	$(Q)# be read at all now.
	$(Q)chroot $(ROOTDIR) cp -f $(NEXT_OPENSTACK_HOME_DIR)/etc/cyborg/api-paste.ini $(CYBORG_CONF_DIR)/api-paste.ini
	$(Q)chroot $(ROOTDIR) cp -f $(NEXT_OPENSTACK_HOME_DIR)/etc/cyborg/policy.yaml $(CYBORG_CONF_DIR)/policy.yaml
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg_sudoers ./etc/sudoers.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg.conf.def .$(CYBORG_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg-conductor.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cyborg/cyborg-agent.service ./lib/systemd/system
