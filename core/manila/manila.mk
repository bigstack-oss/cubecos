# Cube SDK
# manila installation

# python-manilaclient owns two things this tree drives: /usr/bin/manila, which hex_sdk
# calls in health_manila_check(), os_manila_init() and migrate_manila_db_post(), and
# the "share" osc plugin entry point.
#
# Those two wanted different venvs between #638 and #636, so it was installed twice.
# #636 took /usr/bin/openstack to caracal, where the api and the standalone cli already
# were, so one install served all three consumers again. The epoxy hop moves only the
# service: /usr/bin/openstack is still the caracal venv's, so the client stays there in
# a block of its own while manila runs from the epoxy one, the same as heat's (#661).
#
# The osc plugin has to sit with the interpreter that runs /usr/bin/openstack, because
# an entry point is only visible to the interpreter it was installed under. `openstack
# share` is reached from sdk_os.sh (os_manila_share_delete and the share-type
# reconcile), so a copy in the wrong venv breaks those four call sites silently. Unlike
# volume/compute/image, share is not built into python-openstackclient; it is a
# separate plugin, which is why cinder could take its client to caracal wholesale and
# manila had to wait.
#
# /usr/bin/manila is the standalone cli hex_sdk drives. #638 took it to caracal with the
# api it queries, 4.8.1 against 18.3.0, and this hop leaves it there: it is the client's
# console script, not the service's, and the other two consumers pin the client to the
# caracal venv anyway. It talks HTTP and negotiates its microversion, so 4.8.1 (max 2.85)
# drives the 20.0.2 api (max 2.89) at 2.85 -- the shape heat's, designate's and cyborg's
# clis already have. The epoxy venv holds a 5.4.1 copy as an openstack-heat requirement
# (heat.mk), and nothing points at it.
#
# manila-ui is the third consumer: it declares
# `Requires-Dist: python-manilaclient (>=2.7.0)` and imports it from 15 modules,
# including manila_ui/api/manila.py and manila_ui/exceptions.py. It moved to caracal
# with horizon in #636, which is what emptied the antelope side out, and it stays there
# with the served horizon.
#
# openstack-manila-ui is replaced by the manila-ui wheel installed further down --
# see the note above it.
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

# https://releases.openstack.org/epoxy/index.html#epoxy-manila -- 20.0.2 is the newest
# 2025.1 release, the same "last numeric revision of the series" rule #638 used to land
# on 18.3.0. The stable releases since 20.0.0 carry two security fixes -- a snapshot of
# another project readable by its UUID (20.0.1, bug 2120650) and resource locks
# filterable by a foreign project UUID (20.0.2, bug 2161287) -- and the fix for shares
# stuck in "ensuring" behind a driver without bulk ensure_shares (bug 2127023), which
# the generic driver is. The <world> fix #638 relied on is still upstream's, so there
# is no epoxy_patch/ either.
MANILA_VER := 20.0.2

MANILA_CONF_DIR := /etc/manila
MANILA_DATA_DIR := /usr/share/manila
MANILA_APP_DIR := /var/lib/manila
MANILA_LOG_DIR := /var/log/manila
MANILA_RUN_DIR := /var/run/manila

MANILA_SRCDIR := $(ROOTDIR)$(NEXT_OPENSTACK_HOME_DIR)/lib/python$(NEXT_PYTHON_VER)/site-packages/manila
MANILA_PATCHDIR := $(COREDIR)/manila/$(NEXT_OPENSTACK_RELEASE)_patch

# manila-ui follows horizon, not the manila service: it installs next to horizon
# because that is where collectstatic collects panels from. #636 moved horizon into
# the caracal venv, so this moved with it. 11.0.1 is the caracal release --
# https://releases.openstack.org/caracal/index.html#caracal-manila-ui. Horizon plugins
# are not in the upper-constraints (that file only covers libraries), so the pin is
# explicit. It stays the caracal release when the service moves to epoxy, for the same
# reason: the served horizon is still the caracal venv's.
MANILA_UI_VER := 11.0.1

# install manila into the epoxy venv
#
# manila runs out of the epoxy venv, not the caracal one it shares with the 2024.1
# services still there. It cannot be bumped in place: 20.x requires oslo.policy>=4.5.0,
# which os-caracal-pip-upper-constraints.txt holds at 4.3.0 for octavia and the other
# 2024.1 services. So the service moves alone into $(NEXT_OPENSTACK_HOME_DIR), the same
# shape as its caracal hop (#638), one release on, after keystone, glance, cinder,
# nova/placement, neutron, barbican, cyborg, designate, heat and ironic.
#
# Three packages have to be named because manila's requirements.txt asks for none of
# them and pip will not pull them in transitively:
# PyMySQL: config_manila.cpp writes a mysql+pymysql:// connection
# oslo.messaging[kafka]: config_manila.cpp points the notification transport at
#   kafka://
# python-memcached: config_manila.cpp writes [keystone_authtoken] memcached_servers,
#   which makes keystonemiddleware import memcache on its first token validation
# All three happen to be in this venv already, but a dependency nothing asks for is
# one that disappears silently.
#
# The /usr/bin/manila-* links follow the service: the units, config_manila.cpp and
# hex_sdk's migrate_manila_db all reach manila through them.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(NEXT_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			manila==$(MANILA_VER) \
			PyMySQL \
			\"oslo.messaging[kafka]\" \
			python-memcached"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries. This is exactly the set the rpms put in /usr/bin, which is
	$(Q)# every console script 20.0.2 declares. manila-all, which the RDO spec deleted
	$(Q)# before packaging ("files unneeded in production"), is no longer declared at
	$(Q)# all: upstream dropped the broken script (bug 2097445). 2025.1 adds none.
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/manila-api /usr/bin/manila-api
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/manila-data /usr/bin/manila-data
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/manila-manage /usr/bin/manila-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/manila-rootwrap /usr/bin/manila-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/manila-scheduler /usr/bin/manila-scheduler
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/manila-share /usr/bin/manila-share
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/manila-status /usr/bin/manila-status
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/manila-wsgi /usr/bin/manila-wsgi

# the client, its osc plugin and its cli
#
# python-manilaclient stays in the caracal venv next to /usr/bin/openstack and
# manila-ui -- see the note at the top. No version is named:
# os-caracal-pip-upper-constraints.txt already carries python-manilaclient, so a
# version here could only drift from that file.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			python-manilaclient"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# manila is the client's cli, not the service's: $$MANILA in
	$(Q)# core/sdk_sh/modules.pre/sdk_01-var-static.sh is /usr/bin/manila, the path
	$(Q)# python3-manilaclient used to own. The rpm also shipped /usr/bin/manila-3,
	$(Q)# the Fedora python3 alias, which nothing calls and which is not recreated.
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/manila /usr/bin/manila

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

# No $(MANILA_PATCHDIR) exists at caracal or at epoxy, and the guard below is what makes
# that a no-op rather than an error. antelope_patch/ carried exactly one line -- a
# `<world>` -> `*` rewrite in NFSHelper.get_host_list(), because `exportfs` prints
# `<world>` for a wildcard export and manila's parser wanted `*`. Upstream landed its
# own version of that fix, per-entry rather than over the whole blob (so it cannot also
# rewrite a `<world>` inside a path, which ours could), and 18.3.0 is the first tag
# carrying it. The hook is kept so the next hop only has to create the directory.
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
	$(Q)# entry of filters_path in rootwrap.conf. All three are byte-identical between
	$(Q)# 18.3.0 and 20.0.2, so the hop moves only which venv prefix they are read from.
	$(Q)# 0644, not 0640: the spec's %files marks both %attr(-, root, manila), i.e.
	$(Q)# keep whatever mode the build produced, and `mv` off the wheel leaves 0644.
	$(Q)# Verified against cc1, where both are -rw-r--r-- root:manila.
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 $(NEXT_OPENSTACK_HOME_DIR)/etc/manila/api-paste.ini $(MANILA_CONF_DIR)/api-paste.ini
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 $(NEXT_OPENSTACK_HOME_DIR)/etc/manila/rootwrap.conf $(MANILA_CONF_DIR)/rootwrap.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 $(NEXT_OPENSTACK_HOME_DIR)/etc/manila/rootwrap.d/share.filters $(MANILA_DATA_DIR)/rootwrap/share.filters
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
	$(Q)# empty file is what keeps the two from fighting; feeding it the 20.0.2
	$(Q)# sample would only add [oslo_reports].
	$(Q)touch $(ROOTDIR)$(MANILA_CONF_DIR)/manila.conf.def
