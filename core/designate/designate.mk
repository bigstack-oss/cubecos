# Cube SDK
# designate installation

# named is ISC's own build of BIND 9.20, from ISC's COPR project isc/bind, in place of the distro's
# bind 9.16: Stream 9 ships 9.16, and some fixes land only in 9.20. ISC builds it as a software
# collection under /opt/isc/isc-bind, so no path collides with the distro's, and its binaries find
# their own libraries through a RUNPATH. Nothing else in the image requires any of the distro bind
# family, so all of it is blocklisted, which also keeps a cached 9.16 rpm from installing.
#
# What the distro packages provided, and the install block further down replaces:
# - named.service: ours, running ISC's named against /etc/named.conf under the unit name
#   config_designate.cpp and the health checks use. ISC's isc-bind-named reads the collection's own
#   config instead and is masked, so two nameds never share :53 and :953.
# - rndc and rndc-confgen, which designate's rootwrap and config_designate.cpp run, and the
#   bind-utils tools, dig among them for the health check's resolver probe: linked into /usr/sbin
#   and /usr/bin.
# - /var/named, the directory named.conf names.
# ISC's %post also generates an rndc.key for the collection. named.conf takes designate's key, and a
# key generated at build time would be the same on every node, so it is removed.
#
# The build has no LMDB, so named keeps the zones designate adds in _default.nzf rather than 9.16's
# _default.nzd. Nothing converts one into the other because nothing carries /var/named across an
# upgrade: the new root starts with the image's empty one either way.
#
# COPR deletes a project's older builds about two weeks after a newer one succeeds, so CI points
# COPR_DL_HOST at a mirror that keeps these files. Each rpm is pinned by its sha256, taken from a
# copy that verified against the project's key (490C4AE63D8A6B24A6412C8DED4A0B1BC35B531D).
ISC_BIND_RPMS := \
	isc-bind-bind-9.20.30-1.1.el9 \
	isc-bind-bind-libs-9.20.30-1.1.el9 \
	isc-bind-bind-utils-9.20.30-1.1.el9 \
	isc-bind-fstrm-0.6.1-4.el9 \
	isc-bind-fstrm-utils-0.6.1-4.el9 \
	isc-bind-jemalloc-5.3.0-13.el9 \
	isc-bind-libuv-1.49.2-1.el9 \
	isc-bind-protobuf-c-1.5.1-1.el9 \
	isc-bind-runtime-2-4.el9
ROOTFS_DNF_DL_FROM += $(foreach p,$(ISC_BIND_RPMS),$(COPR_DL_HOST)/results/isc/bind/epel-9-x86_64/Packages/i/$(p).x86_64.rpm)
PINNED_DNF += b4807c0c3a62ea085c31e768f65cea297db7f47271a91b047933c786511f9429 isc-bind-bind-9.20.30-1.1.el9.x86_64.rpm
PINNED_DNF += ed049fbee0a79e0fd6486d5122530977b03d9eacf37be07418b7b0bfdd9aff35 isc-bind-bind-libs-9.20.30-1.1.el9.x86_64.rpm
PINNED_DNF += 7f962ac4c7a189e28dab1a6d9c134ab8c57a2e234debcc288af860af0886fd04 isc-bind-bind-utils-9.20.30-1.1.el9.x86_64.rpm
PINNED_DNF += 1551926ef4386690f2a47f520d809fe9ba81868af7b4462c99046595ef9b4245 isc-bind-fstrm-0.6.1-4.el9.x86_64.rpm
PINNED_DNF += d7271d17c6f97f024e20fb33893607fa1b96cbfa95e968b13926473888c8a428 isc-bind-fstrm-utils-0.6.1-4.el9.x86_64.rpm
PINNED_DNF += cf6174bab1ef530eaac0b447971fd561e77e1f5302d6b1a897629853a95660b9 isc-bind-jemalloc-5.3.0-13.el9.x86_64.rpm
PINNED_DNF += 822a54551bbbf3edd3b424018ad7979c9667a04b0d415583f018ed3b40cbdaf3 isc-bind-libuv-1.49.2-1.el9.x86_64.rpm
PINNED_DNF += 5a7d5d57d2d73178a06a43eebcf8dc0785c837c09e4e6224239246847c503ee1 isc-bind-protobuf-c-1.5.1-1.el9.x86_64.rpm
PINNED_DNF += a4bf7a0024c993c8dcaf34c9ac26b70cd4597ace72df3509a15fdedd8e4ec913 isc-bind-runtime-2-4.el9.x86_64.rpm
BLKLST_DNF += bind bind-utils bind-libs bind-license bind-dnssec-utils bind-dnssec-doc python3-bind
ISC_BIND_ROOT := /opt/isc/isc-bind/root

# python-designateclient owns the "dns" osc plugin entry point, which hex_sdk's
# health_designate_check() drives as `openstack dns service list`, counting the
# api/central/worker/producer/mdns rows that report UP. It is installed by its own
# block further down, which #634 split out to hold it in the antelope venv while the
# service moved to caracal. #636 took /usr/bin/openstack to caracal too, which closed
# the split; the epoxy hop opened it again (#660), and #662 closed it the same way by
# taking the cli to epoxy, so the block installs the client beside the service.
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

# https://releases.openstack.org/epoxy/index.html#epoxy-designate-dashboard -- 20.0.1
# is the newest 2025.1 release.
# Horizon plugins are not in the upper-constraints (that file only covers libraries),
# so the pin is explicit. This was a $(OPS_GITHUB_BRANCH_02) clone until #636, which
# turned it into a number when the panel followed horizon into the caracal venv; #662
# took it on to epoxy with horizon. The panel follows horizon, not designate, and talks
# to the service only through its REST API, which is why it could stay a release
# behind the service while horizon did.
DESIGNATE_DASHBOARD_VER := 20.0.1

DESIGNATE_CONF_DIR := /etc/designate
DESIGNATE_APP_DIR := /var/lib/designate
DESIGNAT_LOG_DIR := /var/log/designate

# The console scripts patched below live in the epoxy venv with the service, and so,
# since #662, do the dashboard and the osc plugin -- see the install blocks.
DESIGNATE_BINDIR := $(ROOTDIR)$(OPENSTACK_HOME_DIR)/bin
DESIGNATE_BIN_PATCHDIR := $(COREDIR)/designate/$(OPENSTACK_RELEASE)_bin_patch

# install designate into the epoxy venv
#
# designate runs out of the epoxy venv, not the caracal one it shared with every
# other 2024.1 service. 20.0.2 is the newest 2025.1 release: 20.0.0 was the cycle's,
# and the two point releases on stable/2025.1 add bug fixes only, the last of them
# the cross-pool zone ownership check (bug 2160533). It could not be bumped in place:
# 20.x requires oslo.policy>=4.5.0, which os-caracal-pip-upper-constraints.txt held
# at 4.3.0 for octavia, heat, manila and the other 2024.1 services then in the
# caracal venv. So the service moved alone into $(OPENSTACK_HOME_DIR), the same
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
	$(Q)chroot $(ROOTDIR) bash -c "source $(OPENSTACK_HOME_DIR)/bin/activate && \
		$(OPENSTACK_PIP_INSTALL) -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		designate==20.0.2 \
		PyMySQL \
		\"oslo.messaging[kafka]\" \
		python-memcached"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/designate-api /usr/bin/designate-api
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/designate-api-wsgi /usr/bin/designate-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/designate-central /usr/bin/designate-central
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/designate-manage /usr/bin/designate-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/designate-mdns /usr/bin/designate-mdns
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/designate-producer /usr/bin/designate-producer
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/designate-rootwrap /usr/bin/designate-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/designate-sink /usr/bin/designate-sink
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/designate-status /usr/bin/designate-status
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/designate-worker /usr/bin/designate-worker

# the osc plugin and the dashboard
#
# python-designateclient owns the "dns" osc plugin entry point, and a stevedore entry
# point is only visible to the interpreter it was installed under, so the plugin has
# to sit next to /usr/bin/openstack or health_designate_check()'s `openstack dns
# service list` cannot run at all -- which is how this was first found, as
# "DNSaaS NG [ designate(9 api not all up) ]" while every designate unit was active.
# That held it in the antelope venv from #634 until #636 moved the cli to caracal,
# and in the caracal venv from #660 until #662 moved it to epoxy. The service
# requires the client too, so in the epoxy venv this line is a re-declaration; it is
# named anyway, for the cli, for the reason the note at the top gives.
#
# designate-dashboard is a horizon plugin: core/horizon/horizon.mk copies its enabled
# panels out of $(HORIZON_VENV_SP), which is the site-packages of whichever venv
# horizon runs in, so the dashboard goes where horizon goes. #662 took horizon to
# epoxy, so the panel is an epoxy-venv install now.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_PIP_INSTALL) \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-designateclient
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_PIP_INSTALL) \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		designate-dashboard==$(DESIGNATE_DASHBOARD_VER)
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# install custom files
# for designate
rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/named/named.conf.in ./etc/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/named/named.service ./lib/systemd/system
	$(Q)chroot $(ROOTDIR) systemctl mask isc-bind-named
	$(Q)rm -f $(ROOTDIR)/etc/opt/isc/scls/isc-bind/rndc.key
	$(Q)chroot $(ROOTDIR) ln -sf $(ISC_BIND_ROOT)/usr/sbin/rndc /usr/sbin/rndc
	$(Q)chroot $(ROOTDIR) ln -sf $(ISC_BIND_ROOT)/usr/sbin/rndc-confgen /usr/sbin/rndc-confgen
	$(Q)for b in dig host nslookup nsupdate delv named-checkconf named-checkzone ; do \
		chroot $(ROOTDIR) ln -sf $(ISC_BIND_ROOT)/usr/bin/$$b /usr/bin/$$b || exit 1 ; done
	$(Q)chroot $(ROOTDIR) install -d -m 0770 $(NAMED_APP_DIR)
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
	$(Q)chroot $(ROOTDIR) cp -f $(OPENSTACK_HOME_DIR)/etc/designate/api-paste.ini $(DESIGNATE_CONF_DIR)/api-paste.ini
	$(Q)chroot $(ROOTDIR) cp -f $(OPENSTACK_HOME_DIR)/etc/designate/rootwrap.conf $(DESIGNATE_CONF_DIR)/rootwrap.conf
	$(Q)chroot $(ROOTDIR) cp -rf $(OPENSTACK_HOME_DIR)/etc/designate/rootwrap.d $(DESIGNATE_CONF_DIR)/
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
