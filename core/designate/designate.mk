# Cube SDK
# designate installation

ROOTFS_DNF += bind bind-utils

# python-designateclient owns the "dns" osc plugin entry point, which hex_sdk's
# health_designate_check() drives as `openstack dns service list`, counting the
# api/central/worker/producer/mdns rows that report UP. It is installed by its own
# block further down, which #634 split out to hold it in the antelope venv while the
# service moved to caracal. #636 took /usr/bin/openstack to caracal too, which closed
# the split; the epoxy hop opens it again, so the block holds the client in the
# caracal venv while the service runs from the epoxy one.
#
# It used to be the yoga python3-designateclient rpm under the *system* python 3.9,
# because /usr/bin/openstack was itself `#!/usr/bin/python3` and a stevedore entry point
# is only visible to the interpreter it was installed under. core/heavyfs moved the cli
# into a venv, so the plugin follows it and the rpm is gone.
#
# It is still named explicitly rather than left to designate-dashboard's requirements,
# for the same reason it had to be named as an rpm: it once arrived only as a side effect
# of the yoga horizon closure that #609 removed, and when that closure went so did the
# client, silently. `cluster check` then reported "DNSaaS NG [ designate(9 api not all
# up) ]" while every designate unit was active, because the check could not run its query
# at all.

NAMED_CONF_FILES := /etc/named*
NAMED_APP_DIR := /var/named

# https://releases.openstack.org/caracal/index.html#caracal-designate-dashboard
# Horizon plugins are not in the upper-constraints (that file only covers libraries),
# so the pin is explicit. This was a $(OPS_GITHUB_BRANCH_02) clone until #636: the
# branch name was chosen while the dashboard had to match an antelope horizon, and a
# branch resolves to whatever its tip is on build day. Now that the panel follows
# horizon into the caracal venv the version has to change anyway, so it changes to a
# number. It stays the caracal release when the service moves to epoxy: the panel
# follows horizon, not designate, and talks to the service only through its REST API.
DESIGNATE_DASHBOARD_VER := 18.0.0

DESIGNATE_CONF_DIR := /etc/designate
DESIGNATE_APP_DIR := /var/lib/designate
DESIGNAT_LOG_DIR := /var/log/designate

# The console scripts patched below live in the epoxy venv with the service. The
# dashboard and the osc plugin do not follow it there -- see the install blocks.
DESIGNATE_BINDIR := $(ROOTDIR)$(NEXT_OPENSTACK_HOME_DIR)/bin
DESIGNATE_BIN_PATCHDIR := $(COREDIR)/designate/$(NEXT_OPENSTACK_RELEASE)_bin_patch

# install designate into the epoxy venv
#
# designate runs out of the epoxy venv, not the caracal one it shares with every
# other 2024.1 service. 20.0.2 is the newest 2025.1 release: 20.0.0 was the cycle's,
# and the two point releases on stable/2025.1 add bug fixes only, the last of them
# the cross-pool zone ownership check (bug 2160533). It cannot be bumped in place:
# 20.x requires oslo.policy>=4.5.0, which os-caracal-pip-upper-constraints.txt holds
# at 4.3.0 for octavia, heat, manila and the other 2024.1 services still in the
# caracal venv. So the service moves alone into $(NEXT_OPENSTACK_HOME_DIR), the same
# shape as its caracal hop (#634), one release on, after keystone, glance, cinder,
# nova/placement, neutron, barbican and cyborg.
#
# Three packages have to be named because designate's requirements.txt asks for
# none of them and pip will not pull them in transitively:
# PyMySQL: config_designate.cpp writes a mysql+pymysql:// connection
# oslo.messaging[kafka]: config_designate.cpp points the notification transport at
#   kafka://
# python-memcached: config_designate.cpp writes [keystone_authtoken]
#   memcached_servers, which makes keystonemiddleware import memcache on its first
#   token validation
# All three happen to be in this venv already, but a dependency nothing asks for is
# one that disappears silently.
#
# The /usr/bin/designate-* links follow the service: the five units,
# config_designate.cpp, hex_sdk's migrate_designate_db and the sudoers rule all
# reach designate through them. designate-rootwrap is the one that matters beyond
# startup: the worker runs every rndc call through `sudo designate-rootwrap`, and
# sudo matches the rule by that /usr/bin path, so the rule needs no edit.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(NEXT_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		designate==20.0.2 \
		PyMySQL \
		\"oslo.messaging[kafka]\" \
		python-memcached"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/designate-api /usr/bin/designate-api
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/designate-api-wsgi /usr/bin/designate-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/designate-central /usr/bin/designate-central
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/designate-manage /usr/bin/designate-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/designate-mdns /usr/bin/designate-mdns
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/designate-producer /usr/bin/designate-producer
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/designate-rootwrap /usr/bin/designate-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/designate-sink /usr/bin/designate-sink
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/designate-status /usr/bin/designate-status
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/designate-worker /usr/bin/designate-worker

# the osc plugin and the dashboard
#
# python-designateclient owns the "dns" osc plugin entry point, and a stevedore entry
# point is only visible to the interpreter it was installed under, so the plugin has
# to sit next to /usr/bin/openstack or health_designate_check()'s `openstack dns
# service list` cannot run at all -- which is how this was first found, as
# "DNSaaS NG [ designate(9 api not all up) ]" while every designate unit was active.
# That held it in the antelope venv from #634 until #636 moved the cli here. The
# epoxy hop opens the split once more: /usr/bin/openstack is still the caracal
# venv's, so the client stays here until the cli moves too, the same as barbican's
# (#658) and cyborg's (#659). The epoxy venv gets its own copy as a designate
# requirement, and nothing points at it.
#
# designate-dashboard is a horizon plugin: core/horizon/horizon.mk copies its enabled
# panels out of $(HORIZON_VENV_SP), which is the site-packages of whichever venv
# horizon runs in, so the dashboard goes where horizon goes. #636 took horizon to
# caracal, and the epoxy horizon copy in horizon.mk serves nothing, so the panel is
# still a caracal-venv install.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-designateclient
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		designate-dashboard==$(DESIGNATE_DASHBOARD_VER)
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# install custom files
# for designate
rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/named/named.conf.in ./etc/
	$(Q)chroot $(ROOTDIR) sh -c "chown named:named $(NAMED_CONF_FILES) $(NAMED_APP_DIR)"

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(DESIGNATE_CONF_DIR) $(DESIGNATE_APP_DIR) $(DESIGNAT_LOG_DIR)
	$(Q)chroot $(ROOTDIR) chown designate:designate $(DESIGNATE_CONF_DIR) $(DESIGNATE_APP_DIR) $(DESIGNAT_LOG_DIR)
	$(Q)# api-paste.ini, rootwrap.conf and the rootwrap filters come out of the venv
	$(Q)# prefix rather than a checked-in copy: designate's setup.cfg data_files puts
	$(Q)# them there, and taking them from the install means they track the pinned
	$(Q)# version instead of going stale silently. cinder.mk and glance.mk do the same.
	$(Q)# They used to be copied from the git checkout, which pip replaced in #634.
	$(Q)# 20.0.0 ships rootwrap.conf under its real name instead of as
	$(Q)# rootwrap.conf.sample; the content is unchanged.
	$(Q)chroot $(ROOTDIR) cp -f $(NEXT_OPENSTACK_HOME_DIR)/etc/designate/api-paste.ini $(DESIGNATE_CONF_DIR)/api-paste.ini
	$(Q)chroot $(ROOTDIR) cp -f $(NEXT_OPENSTACK_HOME_DIR)/etc/designate/rootwrap.conf $(DESIGNATE_CONF_DIR)/rootwrap.conf
	$(Q)chroot $(ROOTDIR) cp -rf $(NEXT_OPENSTACK_HOME_DIR)/etc/designate/rootwrap.d $(DESIGNATE_CONF_DIR)/
	$(Q)# policy.yaml.sample is the one file designate's data_files does *not* ship, so
	$(Q)# there is no venv prefix copy to take. It is generated from upstream's
	$(Q)# designate-policy-generator.conf and checked in, the same way designate.conf.sample
	$(Q)# is -- all comments, so it changes no behaviour, but it keeps the file operators
	$(Q)# edit today in place.
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/designate/policy.yaml.sample .$(DESIGNATE_CONF_DIR)/policy.yaml
	$(Q)# -f: treat the destination as the full target path. Without it the install
	$(Q)# script takes designate.conf.def for a directory and drops the sample
	$(Q)# inside it, so config_designate.cpp's LoadConfig() finds nothing to read.
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/designate/designate.conf.sample .$(DESIGNATE_CONF_DIR)/designate.conf.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate_sudoers ./etc/sudoers.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-central.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-worker.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-producer.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-mdns.service ./lib/systemd/system

rootfs_install::
	$(Q)[ -d $(DESIGNATE_BIN_PATCHDIR) ] && cp -rf $(DESIGNATE_BIN_PATCHDIR)/* $(DESIGNATE_BINDIR)/ || /bin/true
