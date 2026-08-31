# Cube SDK
# heat installation

# python-heatclient owns the `orchestration` subcommand ([openstack.cli.extension]
# orchestration = heatclient.osc.plugin), which hex_sdk's health_heat_check() runs
# as `openstack orchestration service list`. Without it `cluster check` reports
# Orchestration NG (errcode 3, "engine down") even when heat-engine is perfectly
# healthy.
#
# It used to be the yoga python3-heatclient rpm under the *system* python, because
# /usr/bin/openstack was `#!/usr/bin/python3` (3.9) and the copy pip put in the 3.10
# venv was invisible to it -- an entry point is only visible to the interpreter it
# was installed under. core/heavyfs moved the CLI into the venv, so the plugin
# followed it.
#
# It stays in the *antelope* venv now that heat itself has moved to caracal, for that
# same entry-point reason: core/heavyfs still links /usr/bin/openstack at
# $(OPENSTACK_HOME_DIR), so the `orchestration` plugin has to be installed under that
# interpreter or health_heat_check() breaks again. heat's own requirements.txt names
# python-heatclient, so the caracal venv gets a 3.5.0 copy of its own; the antelope
# one is what /usr/bin/openstack sees, and its 3.2.0 talks to a 22.0.1 API, which is
# the supported direction -- `orchestration service list` is /v1/{tenant}/services
# and predates 2023.1. Named explicitly rather than left transitive because nothing
# in the antelope venv would pull it any more.
#
# /usr/bin/heat, the client's own CLI, therefore also stays on the antelope venv: it
# is python-heatclient's console script, not heat's. Nothing in this tree calls it,
# but it has always been on the image for operators. /usr/bin/heat-3, the Fedora
# python3 alias, is not recreated -- no other venv console script here is aliased
# that way.
#
# Nothing else is needed: the RDO spec's only non-python Requires was
# shadow-utils, for the heat user and group, and core/heavyfs/account/centos9
# already carries heat statically.
#
# openstack-heat-ui, the Horizon dashboard plugin, is replaced by the
# heat-dashboard wheel installed further down. It was dropped when heat moved to
# pip because horizon was still on python 3.9; #609 moved horizon into the venv, so
# the Orchestration panels come back here. That wheel does *not* follow heat to
# caracal -- see the note above it.

HEAT_CONFDIR := $(ROOTDIR)/etc/heat

# the release is needed twice: once to pin the wheel, once for [revision] heat_revision
# https://releases.openstack.org/caracal/index.html#caracal-heat -- last numeric
# 2024.1 revision, the same rule #1191 used to land on 20.0.1.
HEAT_VER := 22.0.1

# heat-dashboard follows horizon, not the heat service: it installs next to horizon
# because that is where collectstatic collects panels from. #636 moved horizon into
# the caracal venv, so this moved with it. 11.0.0 is the caracal release --
# https://releases.openstack.org/caracal/index.html#caracal-heat-dashboard. There is
# no 11.0.1: the comment this replaces named one, and it does not exist on PyPI.
# heat-dashboard talks to the API over HTTP through heatclient and imports nothing
# from heat, so it never had to move when the service did. Horizon plugins are not in
# the upper-constraints (that file only covers libraries), so the pin is explicit.
HEAT_DASHBOARD_VER := 11.0.0

# install heat
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)# python-heatclient owns the "orchestration" osc plugin and /usr/bin/heat. It
	$(Q)# is named explicitly: an entry point is only visible to the interpreter
	$(Q)# /usr/bin/openstack runs under, so a dependency nothing asks for is one that
	$(Q)# can disappear silently and take `openstack orchestration ...` with it.
	$(Q)chroot $(ROOTDIR) bash -c "source $(CARACAL_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			openstack-heat==$(HEAT_VER) \
			python-heatclient"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link the six console scripts heat declares. The venv also gains
	$(Q)# heat-db-setup and heat-keystone-setup{,-domain} (manual deployment helpers
	$(Q)# that hex_config replaces) and heat-wsgi-api{,-cfn} (only used when heat is
	$(Q)# hosted under a wsgi server, which is not the layout here); those are left
	$(Q)# unlinked on purpose. 2024.1 adds none and removes none.
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/heat-all /usr/bin/heat-all
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/heat-api /usr/bin/heat-api
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/heat-api-cfn /usr/bin/heat-api-cfn
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/heat-engine /usr/bin/heat-engine
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/heat-manage /usr/bin/heat-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/heat-status /usr/bin/heat-status
	$(Q)# the heatclient CLI, which is python-heatclient's console script.
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/heat /usr/bin/heat

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/heat
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/heat

# stage the checked-in sample config and systemd units
# NOTE: core/heat/oslo-config-generator/heat.conf is not staged. It is the input
# that produced heat.conf.sample and is kept in the repo for the next release
# hop; the image has no use for it.
rootfs_install::
	$(Q)cp -f $(COREDIR)/heat/heat.conf.sample $(ROOTDIR)/tmp/heat/
	$(Q)cp -f $(COREDIR)/heat/openstack-heat-api.service $(ROOTDIR)/tmp/heat/
	$(Q)cp -f $(COREDIR)/heat/openstack-heat-api-cfn.service $(ROOTDIR)/tmp/heat/
	$(Q)cp -f $(COREDIR)/heat/openstack-heat-engine.service $(ROOTDIR)/tmp/heat/
	$(Q)cp -f $(COREDIR)/heat/openstack-heat-all.service $(ROOTDIR)/tmp/heat/

# install system directories and files
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/heat
	$(Q)chroot $(ROOTDIR) install -d -m 755 /usr/share/heat
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/heat
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/log/heat
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/run/heat
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/heat/heat.conf.sample /etc/heat/heat.conf
	$(Q)# api-paste.ini, environment.d and templates ship inside the wheel, so
	$(Q)# pip lands them under the venv prefix; relocate them into /etc/heat the
	$(Q)# same way the RDO spec's %install does. All three are byte-identical
	$(Q)# between 20.0.1 and 22.0.1, and heat's data_files list is unchanged, so
	$(Q)# the hop moves only where they are read from.
	$(Q)chroot $(ROOTDIR) cp -f $(CARACAL_OPENSTACK_HOME_DIR)/etc/heat/api-paste.ini /etc/heat/api-paste.ini
	$(Q)chroot $(ROOTDIR) cp -rf $(CARACAL_OPENSTACK_HOME_DIR)/etc/heat/environment.d /etc/heat/
	$(Q)chroot $(ROOTDIR) cp -rf $(CARACAL_OPENSTACK_HOME_DIR)/etc/heat/templates /etc/heat/
	$(Q)# install systemd unit files
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/heat/openstack-heat-api.service /usr/lib/systemd/system/openstack-heat-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/heat/openstack-heat-api-cfn.service /usr/lib/systemd/system/openstack-heat-api-cfn.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/heat/openstack-heat-engine.service /usr/lib/systemd/system/openstack-heat-engine.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/heat/openstack-heat-all.service /usr/lib/systemd/system/openstack-heat-all.service

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chown root:heat /etc/heat/heat.conf
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/heat/heat.conf
	$(Q)chroot $(ROOTDIR) chown root:heat /etc/heat/api-paste.ini
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/heat/api-paste.ini
	$(Q)chroot $(ROOTDIR) chown -R root:heat /etc/heat/environment.d
	$(Q)chroot $(ROOTDIR) chown -R root:heat /etc/heat/templates
	$(Q)chroot $(ROOTDIR) chown heat:heat /var/lib/heat
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/lib/heat
	$(Q)chroot $(ROOTDIR) chown heat:heat /var/log/heat
	$(Q)chroot $(ROOTDIR) chmod 0750 /var/log/heat
	$(Q)chroot $(ROOTDIR) chown heat:heat /var/run/heat
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/run/heat

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/heat

# heat-dist.conf is not shipped (see openstack-heat-api.service), and everything it
# carried is either dead, already written by config_heat.cpp, or a restatement of the
# option's own default -- except one line. The RDO spec appends
# "[revision] heat_revision=%{version}" to that file at build time, and heat serves the
# value from heat/api/openstack/v1/build_info.py, so without it
# GET /v1/{tenant}/build_info reports the "unknown" default instead of the release. Fill
# the key in here rather than editing heat.conf.sample, which has to stay byte-identical
# to what oslo-config-generator produces.
rootfs_install::
	$(Q)sed -i '/^\[revision\]$$/a heat_revision = $(HEAT_VER)' $(HEAT_CONFDIR)/heat.conf

# hex_config reads this baseline and regenerates /etc/heat/heat.conf from it, so
# it has to be taken after the install step above has replaced the file the RPMs
# used to provide. LoadConfig() parses real key/values out of the .def too, not just
# section names, which is what carries heat_revision into every regenerated heat.conf.
rootfs_install::
	$(Q)cp -f $(HEAT_CONFDIR)/heat.conf $(HEAT_CONFDIR)/heat.conf.def

# install the heat web ui plugin, the openstack-heat-ui rpm's replacement.
# Registering its panels, settings snippet and policy files is core/horizon's job:
# every dashboard action lives there, because horizon is built last and is what runs
# collectstatic and compress. Unlike the other components' panels this one needs no
# entry in HORIZON_POLICY_NS: heat-dashboard ships a pre-generated
# conf/default_policies/heat.yaml, so horizon copies it instead of dumping the
# `heat` oslo.policy namespace out of a venv.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) $(CARACAL_OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		heat-dashboard==$(HEAT_DASHBOARD_VER)
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
