# Cube SDK
# octavia installation

# python-octaviaclient owns the `loadbalancer` subcommand, a stevedore entry point.
# core/sdk_sh/modules/sdk_os.sh drives octavia entirely through it -- `loadbalancer
# list` (L404), the four flavorprofile/flavor pairs created at bootstrap
# (L1580-L1602) and `loadbalancer delete --cascade` (L1835) -- so without it the load
# balancer bootstrap and teardown paths break.
#
# It used to be the yoga python3-octaviaclient rpm under the *system* python 3.9,
# because /usr/bin/openstack was `#!/usr/bin/python3` and an entry point is only
# visible to the interpreter it was installed under. #1206 moved it into the 3.10
# venv alongside the CLI. This rpm was also the only hard Requires on
# python3-openstackclient anywhere in the tree, so dropping it there is what let
# core/heavyfs stop installing the yoga CLI.
#
# It stays in the *antelope* venv now that octavia itself has moved to caracal, for
# the same entry-point reason: core/heavyfs still links /usr/bin/openstack at
# $(OPENSTACK_HOME_DIR), so the `loadbalancer` plugin has to be installed under that
# interpreter or the call sites above stop resolving. Unlike manila, there is no
# second consumer -- octavia ships no standalone CLI and nothing in hex_sdk runs one
# -- so the client is installed once, and only there. That leaves the antelope
# constraint's python-octaviaclient 3.4.0 talking to a caracal 14.0.2 API, which is
# the supported direction: octaviaclient negotiates the API version per request and
# every call sdk_os.sh makes (loadbalancer list, the flavorprofile/flavor pairs,
# delete --cascade) predates 2023.1.
#
# NOTE: unlike heat, health_octavia_check() is *not* what depends on this.
# It checks systemd units, the monasca http_status metric and the octavia-hm0
# OVN port, never the OSC CLI -- so `cluster check` would have stayed green
# while the bootstrap paths above failed.
#
# openstack-octavia-ui, the Horizon dashboard plugin, is replaced by the
# octavia-dashboard wheel installed further down. It was dropped when octavia moved
# to pip because Horizon still ran on the system python 3.9 and could not import a
# package from the 3.10 venv; #609 moved Horizon into the venv, so the Load Balancer
# panel comes back. Registering it is core/horizon's job, where every dashboard
# action lives. That wheel does *not* follow octavia to caracal -- see the note
# above it.
#
# The octavia user and group are carried statically by
# core/heavyfs/account/centos9 (uid/gid 138), so the RDO spec's shadow-utils
# requirement has no equivalent here.

OCTAVIA_CONF_DIR := /etc/octavia
OCTAVIA_CONFDIR := $(ROOTDIR)$(OCTAVIA_CONF_DIR)

OCTAVIA_SRCDIR := $(ROOTDIR)$(CARACAL_OPENSTACK_HOME_DIR)/lib/python$(CARACAL_PYTHON_VER)/site-packages/octavia
OCTAVIA_PATCHDIR := $(COREDIR)/octavia/$(CARACAL_OPENSTACK_RELEASE)_patch/octavia

# https://releases.openstack.org/caracal/index.html#caracal-octavia -- last numeric
# 2024.1 revision, the same rule #1206 used to land on 12.0.1. core/octavia/Makefile
# builds the amphora image from this same tag, so the agent inside the image and the
# controllers outside it stay one release.
OCTAVIA_VER := 14.0.2

# Deliberately still the 2023.1 pin, and deliberately still in the antelope venv.
# core/horizon/horizon.mk serves the dashboard out of $(OPENSTACK_HOME_DIR) --
# openstack-dashboard.service, gunicorn-config.py and the httpd reverse proxy all
# point at the antelope tree, and every dashboard plugin installs next to it.
# octavia-dashboard follows horizon, not the octavia service, so the Load Balancer
# panel stays on 11.0.1 until horizon itself hops; 13.0.1 is the caracal release to
# move to on that day. It talks to the API over HTTP and imports nothing from
# octavia, so the split costs nothing. Horizon plugins are not in the
# upper-constraints (that file only covers libraries), so the pin has to be explicit.
OCTAVIA_DASHBOARD_VER := 11.0.1

# install octavia
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)# octavia-lib is NOT in octavia's requirements.txt, but the amphora
	$(Q)# provider driver imports it directly (octavia/api/drivers/
	$(Q)# amphora_driver/v2/driver.py imports octavia_lib.api.drivers), and that
	$(Q)# is the provider this deployment uses. The RPM pulled it in as
	$(Q)# python3-octavia-lib; pip will not, so it is listed explicitly.
	$(Q)#
	$(Q)# kazoo is the same shape of problem, and the venv split is what exposed it.
	$(Q)# config_octavia.cpp writes task_flow/jobboard_backend_driver =
	$(Q)# zookeeper_taskflow_driver, and taskflow's zookeeper jobboard imports kazoo
	$(Q)# -- but that is an *extra* (taskflow[zookeeper]), not a requirement, and
	$(Q)# octavia does not declare it. Under antelope it happened to be present
	$(Q)# anyway, dragged into the shared venv by monasca-common; the caracal venv has
	$(Q)# no monasca, so octavia-worker crash-looped on ModuleNotFoundError: No module
	$(Q)# named 'kazoo' until this line existed. Named here rather than as
	$(Q)# taskflow[zookeeper] to match octavia-lib above, and because the constraint
	$(Q)# file already pins it (2.10.0).
	$(Q)chroot $(ROOTDIR) bash -c "source $(CARACAL_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			octavia==$(OCTAVIA_VER) \
			octavia-lib \
			kazoo"
	$(Q)# and the "loadbalancer" osc plugin in the antelope venv, alone: that entry
	$(Q)# point is only visible to the interpreter /usr/bin/openstack runs under, and
	$(Q)# that is still the antelope one -- see the note at the top of this file.
	$(Q)chroot $(ROOTDIR) bash -c "source $(OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			python-octaviaclient"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link the seven console scripts that run on the controller. The venv
	$(Q)# also gains amphora-agent, amphora-health-checker, amphora-interface,
	$(Q)# haproxy-vrrp-check and prometheus-proxy; those run *inside* the
	$(Q)# amphora VM and are provided by the amphora image, so they are left
	$(Q)# unlinked on purpose. 2024.1 adds an eighth, octavia-wsgi, for serving the
	$(Q)# api under a wsgi container; octavia-api.service execs octavia-api directly,
	$(Q)# so that one is left unlinked too.
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/octavia-api /usr/bin/octavia-api
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/octavia-worker /usr/bin/octavia-worker
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/octavia-health-manager /usr/bin/octavia-health-manager
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/octavia-housekeeping /usr/bin/octavia-housekeeping
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/octavia-db-manage /usr/bin/octavia-db-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/octavia-driver-agent /usr/bin/octavia-driver-agent
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/octavia-status /usr/bin/octavia-status

# Whole-file downstream copies, if any -- anything under PATCHDIR that is not a
# *.py.patch or its *.py.orig. Nothing uses this today: both carried changes are
# unified diffs below.
rootfs_install::
	$(Q)[ -d $(OCTAVIA_PATCHDIR) ] && rsync -a --exclude='*.py.patch' --exclude='*.py.orig' $(OCTAVIA_PATCHDIR)/ $(OCTAVIA_SRCDIR)/ || /bin/true

# Reviewable unified diffs, same convention as core/masakari: each patch sits at
# <PATCHDIR>/<rel>.py.patch and targets <SRCDIR>/<rel>.py, with a <rel>.py.orig
# alongside for review only. Preferred over the whole-file copies above -- a diff
# shows what we changed, and --forward keeps re-runs idempotent while a failed
# hunk aborts the build, so upstream drift is caught here rather than shipped.
#
# Two are carried:
#
#   compute/drivers/nova_driver.py  meta={'HA_Enabled': 'False'} on the amphora
#                                   boot, so masakari does not evacuate amphorae
#   cmd/status.py                   import octavia.common.policy, which is what
#                                   registers the [oslo_policy] group that
#                                   _check_yaml_policy() reads. Without it
#                                   `octavia-status upgrade check` dies with
#                                   "NoSuchOptError: no such option oslo_policy in
#                                   group [DEFAULT]" before printing any result.
#                                   Still upstream's bug at 14.0.2 -- the import
#                                   list is unchanged since 12.0.1, and master's
#                                   is too. #1206 carried this as a whole-file
#                                   copy; a diff is what catches the next drift.
rootfs_install::
	$(Q)set -e; for p in $$(find $(OCTAVIA_PATCHDIR) -name '*.py.patch' 2>/dev/null | sort); do \
		rel=$${p#$(OCTAVIA_PATCHDIR)/}; tgt=$(OCTAVIA_SRCDIR)/$${rel%.patch}; \
		echo "  PATCH   $${rel%.patch}"; \
		patch --forward --no-backup-if-mismatch -r - "$$tgt" < "$$p" \
			|| { echo "octavia: failed to apply $$p to $$tgt" >&2; exit 1; }; \
	done

# install the octavia web ui plugin, the openstack-octavia-ui rpm's replacement.
# Registering its panel and settings snippet is core/horizon's job, where every
# dashboard action lives -- including the generated default_policies/octavia.yaml,
# because the snippet octavia-dashboard ships registers
# POLICY_FILES['load-balancer'] but no file to back it.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)# $(OPENSTACK_HOME_DIR), not the caracal venv: this follows horizon, which
	$(Q)# has not hopped -- see the note by OCTAVIA_DASHBOARD_VER.
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		octavia-dashboard==$(OCTAVIA_DASHBOARD_VER)
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/octavia
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/octavia

# stage the checked-in sample config, policy, dist conf and systemd units
# NOTE: core/octavia/oslo-config-generator/octavia.conf is not staged. It is the
# input that produced octavia.conf.sample and is kept in the repo for the next
# release hop; the image has no use for it.
rootfs_install::
	$(Q)cp -f $(COREDIR)/octavia/octavia.conf.sample $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/policy.yaml $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-dist.conf $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-api.service $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-worker.service $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-housekeeping.service $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-health-manager.service $(ROOTDIR)/tmp/octavia/

# install system directories and files
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia
	$(Q)chroot $(ROOTDIR) install -d -m 755 /usr/share/octavia
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/octavia
	$(Q)chroot $(ROOTDIR) install -d -m 750 /var/log/octavia
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/run/octavia
	$(Q)# per-service drop-in directories the systemd units pass with
	$(Q)# --config-dir; oslo.config fails to start if they do not exist.
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/common
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/octavia-api
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/octavia-worker
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/octavia-housekeeping
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/octavia-health-manager
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/octavia/octavia.conf.sample /etc/octavia/octavia.conf
	$(Q)# policy.yaml reverts the API to the legacy admin-or-owner RBAC, where a
	$(Q)# project member can manage the load balancers they own. Without it the
	$(Q)# stock default RBAC applies and every non-admin call needs an
	$(Q)# explicit load-balancer_* role.
	$(Q)#
	$(Q)# This is a verbatim copy of upstream etc/policy/admin_or_owner-policy.yaml
	$(Q)# (md5 c53952746cfb39f5c66f97bbe3bcb263), which is the same file the RPM
	$(Q)# delivered: openstack-octavia.spec:234 renames that exact path to
	$(Q)# /etc/octavia/policy.yaml and the spec carries no patches at all. That file
	$(Q)# is byte-identical at 12.0.1 and 14.0.2, so the caracal hop does not move
	$(Q)# it either. The 0640 root:octavia set further down matches the %attr the
	$(Q)# spec put on it, so nothing about the effective RBAC moves with this hop.
	$(Q)#
	$(Q)# It has to keep being carried: unlike manila's api-paste.ini or glance's
	$(Q)# metadefs, octavia's wheel data_files are only share/octavia/{LICENSE,
	$(Q)# README.rst,diskimage-create/*} -- nothing under etc/ reaches the venv
	$(Q)# prefix, so there is no installed copy to relocate from.
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/octavia/policy.yaml /etc/octavia/policy.yaml
	$(Q)# 644, not 640: the units run as User=octavia and must be able to read
	$(Q)# this. It holds no secrets.
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-dist.conf /usr/share/octavia/octavia-dist.conf
	$(Q)# certificate tooling (unchanged from the RPM layout)
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/certs
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/octavia/certs/create_certificates.sh .$(OCTAVIA_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/octavia/certs/octavia-certs.cnf .$(OCTAVIA_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/octavia/dhclient.conf .$(OCTAVIA_CONF_DIR)
	$(Q)chroot $(ROOTDIR) chmod 755 /etc/octavia/create_certificates.sh
	$(Q)# install systemd unit files. All four are installed here now; under the
	$(Q)# RPM layout only worker and health-manager were, because
	$(Q)# openstack-octavia-{api,housekeeping} shipped the other two. The two
	$(Q)# units this branch rewrote are verbatim copies of the ones those RPMs
	$(Q)# installed, so dropping the RPMs does not change how they start. Note
	$(Q)# the checked-in files they replaced were never installed by anything --
	$(Q)# that is why they still pointed at /usr/local/bin.
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-api.service /usr/lib/systemd/system/octavia-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-worker.service /usr/lib/systemd/system/octavia-worker.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-housekeeping.service /usr/lib/systemd/system/octavia-housekeeping.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-health-manager.service /usr/lib/systemd/system/octavia-health-manager.service
	$(Q)# gate the health-manager on the planned-maintenance marker: it rebuilds every
	$(Q)# amphora on stale heartbeats, which a planned shutdown otherwise looks like
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/octavia-health-manager.service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/main/cube-planned-maintenance.conf ./etc/systemd/system/octavia-health-manager.service.d/

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chown root:octavia /etc/octavia/octavia.conf
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/octavia/octavia.conf
	$(Q)chroot $(ROOTDIR) chown root:octavia /etc/octavia/policy.yaml
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/octavia/policy.yaml
	$(Q)chroot $(ROOTDIR) chown octavia:octavia /var/lib/octavia
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/lib/octavia
	$(Q)chroot $(ROOTDIR) chown octavia:octavia /var/log/octavia
	$(Q)chroot $(ROOTDIR) chmod 0750 /var/log/octavia
	$(Q)chroot $(ROOTDIR) chown octavia:octavia /var/run/octavia
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/run/octavia

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/octavia

# hex_config reads this baseline and regenerates /etc/octavia/octavia.conf from
# it, so it has to be taken after the install step above has replaced the file
# the RPMs used to provide.
rootfs_install::
	$(Q)cp -f $(OCTAVIA_CONFDIR)/octavia.conf $(OCTAVIA_CONFDIR)/octavia.conf.def
