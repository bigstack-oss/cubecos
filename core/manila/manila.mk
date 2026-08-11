# Cube SDK
# manila installation

# python-manilaclient owns two things this tree drives: /usr/bin/manila, which hex_sdk
# calls in health_manila_check(), os_manila_init() and migrate_manila_db_post(), and
# the "share" osc plugin entry point.
#
# It used to be the yoga python3-manilaclient rpm under the *system* python 3.9,
# because /usr/bin/openstack was itself `#!/usr/bin/python3` and an entry point is
# only visible to the interpreter it was installed under. core/heavyfs moved the cli
# into the 3.10 venv, so the plugin follows it: it is named on the pip install below
# and /usr/bin/manila is relinked into the venv the way every other console script
# here already is. That also retires the yoga-client-against-antelope-api pairing the
# rpm forced -- 4.4.2 is the client antelope's own upper-constraints names for the
# 16.3.0 api installed here.
#
# openstack-manila-ui is replaced by the manila-ui wheel installed further down.
# #609 moved horizon into the 3.10 venv, so the Shares panels can follow the manila
# service in there.
#
# openstack-manila and openstack-manila-share are what the pip install below
# replaces. Non-python Requires of those two that are deliberately not restated:
#   shadow-utils  core/heavyfs/account/centos9 already carries the manila user
#                 and group statically, the same way it does for heat.
#   sudo, lvm2    already installed by core/cinder.
#   samba         only reached from the lvm and container drivers -- they are what
#                 smbd, net and smbcontrol in rootwrap.d/share.filters authorise.
#                 config_manila.cpp pins enabled_share_backends to "generic" and
#                 rewrites it on every Commit(), and the generic driver's
#                 CIFSHelper runs its `net conf` calls through _ssh_exec() inside
#                 the service instance, never on the host.

# https://releases.openstack.org/antelope/index.html#antelope-manila
MANILA_VER := 16.3.0

MANILA_CONF_DIR := /etc/manila
MANILA_DATA_DIR := /usr/share/manila
MANILA_APP_DIR := /var/lib/manila
MANILA_LOG_DIR := /var/log/manila
MANILA_RUN_DIR := /var/run/manila

MANILA_SRCDIR := $(ROOTDIR)/opt/openstack-antelope/lib/python$(PYTHON_VER)/site-packages/manila
MANILA_PATCHDIR := $(COREDIR)/manila/$(OPENSTACK_RELEASE)_patch

# https://releases.openstack.org/antelope/index.html -- last numeric 2023.1
# revision. Horizon plugins are not in the antelope upper-constraints (that file
# only covers libraries), so the pin has to be explicit.
MANILA_UI_VER := 9.0.1

# install manila inside the python 3.10 virtual environment
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)# python-manilaclient is the "share" osc plugin and owns /usr/bin/manila,
	$(Q)# named explicitly -- see the note at the top of this file.
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			manila==$(MANILA_VER) \
			python-manilaclient"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries. This is exactly the set the rpms put in /usr/bin, which is
	$(Q)# every console_script manila declares except manila-all -- the RDO spec
	$(Q)# deletes that one before packaging ("files unneeded in production"), so it
	$(Q)# is left unlinked here as well.
	$(Q)# manila is the client's cli, not the service's: $$MANILA in
	$(Q)# core/sdk_sh/modules.pre/sdk_01-var-static.sh is /usr/bin/manila, the path
	$(Q)# python3-manilaclient used to own. The rpm also shipped /usr/bin/manila-3,
	$(Q)# the Fedora python3 alias, which nothing calls and which is not recreated.
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/manila /usr/bin/manila
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/manila-api /usr/bin/manila-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/manila-data /usr/bin/manila-data
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/manila-manage /usr/bin/manila-manage
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/manila-rootwrap /usr/bin/manila-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/manila-scheduler /usr/bin/manila-scheduler
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/manila-share /usr/bin/manila-share
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/manila-status /usr/bin/manila-status
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/manila-wsgi /usr/bin/manila-wsgi

# install the manila web ui plugin, the openstack-manila-ui rpm's replacement.
# Registering its panels and policy files is core/horizon's job, where every
# dashboard action lives -- including the copy of
# core/manila/local/local_settings.d/_90_manila_shares.py, which overrides the
# snippet manila_ui ships under the same name.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		manila-ui==$(MANILA_UI_VER)
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

rootfs_install::
	$(Q)[ -d $(MANILA_PATCHDIR) ] && cp -rf $(MANILA_PATCHDIR)/* $(MANILA_SRCDIR)/ || /bin/true

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/manila
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/manila

# stage the checked-in sample config, sudoers and systemd units
# NOTE: core/manila/oslo-config-generator/manila.conf is not staged. It is the
# input that produced manila.conf.sample and is kept in the repo for the next
# release hop; the image has no use for it.
rootfs_install::
	$(Q)cp -f $(COREDIR)/manila/manila.conf.sample $(ROOTDIR)/tmp/manila/
	$(Q)cp -f $(COREDIR)/manila/manila-sudoers $(ROOTDIR)/tmp/manila/
	$(Q)cp -f $(COREDIR)/manila/openstack-manila-api.service $(ROOTDIR)/tmp/manila/
	$(Q)cp -f $(COREDIR)/manila/openstack-manila-scheduler.service $(ROOTDIR)/tmp/manila/
	$(Q)cp -f $(COREDIR)/manila/openstack-manila-share.service $(ROOTDIR)/tmp/manila/
	$(Q)cp -f $(COREDIR)/manila/openstack-manila-data.service $(ROOTDIR)/tmp/manila/

# install system directories and files
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(MANILA_CONF_DIR)
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(MANILA_DATA_DIR)
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(MANILA_DATA_DIR)/rootwrap
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(MANILA_APP_DIR)
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(MANILA_APP_DIR)/tmp
	$(Q)chroot $(ROOTDIR) install -d -m 750 $(MANILA_LOG_DIR)
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(MANILA_RUN_DIR)
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/manila/manila.conf.sample $(MANILA_CONF_DIR)/manila.conf
	$(Q)# api-paste.ini, rootwrap.conf and rootwrap.d/share.filters are the wheel's
	$(Q)# data_files, so pip lands them under the venv prefix. Relocate them exactly
	$(Q)# the way the RDO spec's %install does -- note the filters go to
	$(Q)# /usr/share/manila/rootwrap, not /etc/manila/rootwrap.d, which is the second
	$(Q)# entry of filters_path in rootwrap.conf.
	$(Q)# 0644, not 0640: the spec's %files marks both %attr(-, root, manila), i.e.
	$(Q)# keep whatever mode the build produced, and `mv` off the wheel leaves 0644.
	$(Q)# Verified against cc1, where both are -rw-r--r-- root:manila.
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /opt/openstack-antelope/etc/manila/api-paste.ini $(MANILA_CONF_DIR)/api-paste.ini
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /opt/openstack-antelope/etc/manila/rootwrap.conf $(MANILA_CONF_DIR)/rootwrap.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /opt/openstack-antelope/etc/manila/rootwrap.d/share.filters $(MANILA_DATA_DIR)/rootwrap/share.filters
	$(Q)# install security configurations
	$(Q)chroot $(ROOTDIR) install -p -D -m 440 /tmp/manila/manila-sudoers /etc/sudoers.d/manila
	$(Q)# install systemd unit files
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/manila/openstack-manila-api.service /usr/lib/systemd/system/openstack-manila-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/manila/openstack-manila-scheduler.service /usr/lib/systemd/system/openstack-manila-scheduler.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/manila/openstack-manila-share.service /usr/lib/systemd/system/openstack-manila-share.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/manila/openstack-manila-data.service /usr/lib/systemd/system/openstack-manila-data.service

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chown root:manila $(MANILA_CONF_DIR)/manila.conf
	$(Q)chroot $(ROOTDIR) chown root:manila $(MANILA_CONF_DIR)/api-paste.ini
	$(Q)chroot $(ROOTDIR) chown root:manila $(MANILA_CONF_DIR)/rootwrap.conf
	$(Q)chroot $(ROOTDIR) chown manila:manila $(MANILA_APP_DIR)
	$(Q)chroot $(ROOTDIR) chown manila:manila $(MANILA_APP_DIR)/tmp
	$(Q)chroot $(ROOTDIR) chown manila:root $(MANILA_LOG_DIR)
	$(Q)chroot $(ROOTDIR) chown manila:root $(MANILA_RUN_DIR)

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/manila

rootfs_install::
	# configuration changes
	$(Q)cp -f $(ROOTDIR)$(MANILA_CONF_DIR)/manila.conf $(ROOTDIR)$(MANILA_CONF_DIR)/manila.conf.org
	$(Q)# manila.conf.def is deliberately left empty. Unlike every other module,
	$(Q)# config_manila.cpp does not take its section list from the .def:
	$(Q)# InitConfig() spells the sections out, because manila.conf needs a [generic]
	$(Q)# backend section that no generated sample can contain. LoadConfig() on an
	$(Q)# empty file is what keeps the two from fighting; feeding it the antelope
	$(Q)# sample would only add [oslo_reports].
	$(Q)touch $(ROOTDIR)$(MANILA_CONF_DIR)/manila.conf.def
