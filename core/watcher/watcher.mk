# Cube SDK
# watcher installation

# https://releases.openstack.org/epoxy/index.html#epoxy-watcher -- 14.1.2 is the newest
# 2025.1 release, the same "last numeric revision of the series" rule #1204 and #643 used
# to land on 10.0.0 and 12.1.0. Over 14.0.0 it carries upstream's fixes for the
# prometheus host queries (fqdn_label instead of the instance label, host_ram_usage in
# KiB), an action plan now reported FAILED when one of its actions failed rather than
# SUCCEEDED, 400 instead of 500 for a malformed audit, host_maintenance no longer
# migrating onto disabled hosts, a policy check on the webhook trigger, and service
# start/stop logs that no longer print the transport URL.
# stable/2025.1 carries two commits past it, both unreleased: "Add strategy as filter on
# /v1/audits/detail endpoint", an api feature, and "Fix allowed_nodes corruption in
# ComputeScope" (LP#1988981), which only reaches audits scoped by availability zone --
# a pre-existing bug, in 12.1.0 as well, and nothing in this tree creates such an audit.
WATCHER_VER := 14.1.2

WATCHER_CONF_DIR := /etc/watcher
WATCHER_APP_DIR := /var/cache/watcher
WATCHER_LOG_DIR := /var/log/watcher
WATCHER_RUN_DIR := /var/run/watcher

# The service moves into the epoxy venv; the osc plugin and the dashboard do not follow
# it -- see the second install block. WATCHER_SRCDIR deliberately stops at site-packages
# instead of descending into watcher/ the way cyborg.mk, nova.mk and neutron.mk do,
# because the entry point registration at the bottom of this file reaches the dist-info
# directory through it. The patch tree carries its own leading watcher/ to compensate.
#
# The tree follows the same convention as core/nova and core/masakari: a reviewable
# unified diff at <rel>.py.patch beside the pristine <rel>.py.orig it applies to, and
# brand-new downstream files (anything that is not *.patch/*.orig) installed verbatim.
# Watcher used to overlay whole modified copies with cp -rf, which hid what had actually
# been changed and silently absorbed upstream edits on a version bump. A failed hunk
# aborts the build rather than shipping drift.
#
# One deliberate difference from core/nova and core/masakari: those guard the apply with
# `|| exit 1` and rely on --forward for idempotence, but --forward only skips the *hunks* --
# it still exits 1 when every hunk is already applied, so a re-run against an already-patched
# tree aborts the build. That never fires there because each build reinstalls the venv from
# pip first, so the target is always pristine; it would fire in an incremental workspace.
# Testing with --dry-run --reverse first detects the already-applied case and skips it,
# which keeps the convention and makes the loop genuinely re-runnable.
#
# epoxy_patch/ carries two of caracal_patch/'s five changes. The prometheus datasource
# caracal_patch/ backported from 2025.1 is 14.1.2's own now: its datasources/prometheus.py
# and conf/prometheus_client.py were verbatim upstream and are byte-identical to
# 14.1.2's, and 14.1.2's datasources/manager.py and conf/__init__.py register them with
# exactly the lines the two caracal patches added, so all four files go. What is left:
#   decision_engine/strategy/strategies/workload_balance.py
#       the workload_cache.get() guard for an instance the cache does not hold, the
#       note on why ceilometer_memory_usage takes no unit conversion, and the
#       diagnostics at INFO. 14.1.2 adopted the destination-host and host-usage lines
#       itself (d6750e40) at DEBUG, so the patch now raises upstream's own lines
#       instead of adding its own, and the host_metric it computed is upstream's too.
#   decision_engine/strategy/strategies/allocation_balance.py
#       the CubeCOS strategy, installed verbatim and byte-identical to caracal's. It
#       has no upstream counterpart; strategies/base.py is unchanged between 12.1.0
#       and 14.1.2 and the model methods it calls kept their signatures.
WATCHER_SRCDIR := $(ROOTDIR)$(NEXT_OPENSTACK_HOME_DIR)/lib/python$(NEXT_PYTHON_VER)/site-packages
WATCHER_PATCHDIR := $(COREDIR)/watcher/$(NEXT_OPENSTACK_RELEASE)_patch

# https://releases.openstack.org/epoxy/index.html#epoxy-watcher-dashboard -- 13.0.0 is
# the epoxy release, and the only one of the series.
# Horizon plugins are not in the upper-constraints (that file only covers libraries),
# so the pin is explicit. This used to be a git clone of the 2023.1-eol *tag*, because
# watcher-dashboard publishes neither stable/2023.1 nor unmaintained/2023.1 -- both
# branches were deleted at EOL, so there was no branch for installpip's fallback chain
# to resolve. #636 moved the panel to the caracal release, which is on PyPI as a wheel,
# and the tag hack went with it; #662 took it on to epoxy with horizon. The panel talks
# to the api over HTTP, whose maximum microversion is 1.4 in both 12.1.0 and 14.1.2,
# which is why it could stay a release behind the service while horizon did.
WATCHER_DASHBOARD_VER := 13.0.0

# install watcher into the epoxy venv
#
# watcher runs out of the epoxy venv, not the caracal one it shared with horizon,
# skyline and the osc clients. It cannot be bumped in place: 14.x requires
# oslo.policy>=4.5.0 and python-observabilityclient>=0.3.0, which
# os-caracal-pip-upper-constraints.txt holds at 4.3.0 and 0.1.1. So the service moves
# alone into $(NEXT_OPENSTACK_HOME_DIR), the same shape as its caracal hop (#643), one
# release on, after keystone, glance, cinder, nova/placement, neutron, barbican,
# cyborg, designate, heat, ironic, manila, masakari and octavia.
#
# Nothing about the packaging changes -- watcher was already a pinned pip install when
# it lived in the antelope venv, so this hop only moves it. openstack-watcher.spec has
# no watcher-dist.conf, no rootwrap and no sudoers, and it deletes the wheel's whole
# /usr/etc tree -- the only data_files there are the config sample, a README and the
# two generator inputs -- so unlike heat, ironic and manila there is nothing to
# relocate out of the venv prefix. The watcher user and group come from
# core/heavyfs/account/centos9 statically, so shadow-utils is not needed either.
#
# python-observabilityclient, which this file used to name for the backported
# datasource, is in 14.1.2's own requirements.txt now, so it is not named any more.
# Three packages are, because watcher's requirements.txt asks for none of them:
#   PyMySQL                config_watcher.cpp writes a mysql+pymysql:// connection
#   oslo.messaging[kafka]  config_watcher.cpp points the notification transport at
#                          kafka://
#   python-memcached       config_watcher.cpp writes memcached_servers, which makes
#                          keystonemiddleware import memcache on its first token
#                          validation
# All three happen to be in this venv already, but a dependency nothing asks for is
# one that disappears silently.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(NEXT_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			python-watcher==$(WATCHER_VER) \
			PyMySQL \
			\"oslo.messaging[kafka]\" \
			python-memcached"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries. This is exactly the set the rpms put in /usr/bin, which is
	$(Q)# every console_script watcher declares plus the one wsgi_script; 2025.1
	$(Q)# declares the same seven as 2024.1. The units, config_watcher.cpp and
	$(Q)# hex_sdk's migrate_watcher_db all reach the service through these, so the
	$(Q)# retarget here is the whole of their move.
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/watcher-api /usr/bin/watcher-api
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/watcher-api-wsgi /usr/bin/watcher-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/watcher-applier /usr/bin/watcher-applier
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/watcher-db-manage /usr/bin/watcher-db-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/watcher-decision-engine /usr/bin/watcher-decision-engine
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/watcher-status /usr/bin/watcher-status
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/watcher-sync /usr/bin/watcher-sync

# the osc plugin and the web ui plugin
#
# python-watcherclient owns the "optimize" osc plugin entry point, which hex_sdk's
# health_watcher_check() drives as `openstack optimize service list`. A stevedore entry
# point is only visible to the interpreter it was installed under, and /usr/bin/openstack
# is the epoxy venv's since #662, so the plugin lives there or the health check cannot
# run its query at all. It had to stay in antelope while the cli did, which is the
# constraint #632, #633 and #634 also hit for python-barbicanclient,
# python-cyborgclient and python-designateclient, and in caracal from #670, which
# moved only the service, until #662 moved the cli -- the split heat's (#661),
# masakari's (#665) and octavia's (#667) hops made too.
#
# It is named explicitly rather than left to watcher-dashboard's requirements.txt, which
# also asks for it. designate.mk carries the story: a client that arrives only as a side
# effect of some other install disappears silently the day that install moves, and the
# symptom is `cluster check` reporting the service NG while every unit is active. No
# version is named, the same way cyborg.mk does not name one: the epoxy constraints
# file already carries python-watcherclient, so a version here could only drift from it.
#
# watcher-dashboard is a horizon plugin: core/horizon/horizon.mk copies its enabled
# panels out of $(HORIZON_VENV_SP), which is the site-packages of whichever venv
# horizon runs in, so the dashboard goes where horizon goes. #662 took horizon to
# epoxy, so the panel is an epoxy-venv install now.
#
# /usr/bin/watcher is the client's own cli. It used to come from the system python 3.9
# install as /usr/local/bin/watcher -- /usr/bin held only the watcher-* service scripts
# linked above -- and since /usr/local/bin precedes /usr/bin in the PATH hex_sdk sets,
# the replacement is this symlink. It points at the client, so it follows the client
# rather than the watcher-* service links above -- into the epoxy venv with #662.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) $(NEXT_OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-watcherclient
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) $(NEXT_OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		watcher-dashboard==$(WATCHER_DASHBOARD_VER)
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/watcher /usr/bin/watcher

# install system directories and files
#
# watcher.conf.sample is generated and checked in so builds stay reproducible and
# config diffs remain reviewable. It is oslo-config-generator run over
# oslo-config-generator/watcher.conf, which is still byte-identical to upstream's
# copy -- the file did not change between the 10.0.0 and 14.1.2 tags -- over pristine
# upstream sources: the carried .orig files put back and the allocation_balance entry
# point left out, so the sample is upstream's alone. Two adjustments the RDO spec also
# makes or needs:
#   - #pybasedir is stripped; its default is the build path and is meaningless here.
#   - watcher.objects.register_all() is called before the generator, otherwise
#     stevedore fails to load the "taskflow" opts entry point ("module
#     watcher.objects has no attribute action_plan") and the sample silently loses
#     the [watcher_workflow_engines.taskflow] section. 14.1.2 still needs it.
# Regenerated against 14.1.2 the sample loses two sections and gains one, 46 becoming
# 45: [ceilometer_client] goes with the ceilometer datasource upstream removed,
# [oslo_messaging_amqp] with oslo.messaging's AMQP 1.0 driver, and [prometheus_client]
# arrives as upstream's own now that the datasource is. Every option in a generator
# sample is still commented out -- zero uncommented keys before and after -- so
# LoadConfig() reads empty sections as it always did, and the watcher.conf
# config_watcher.cpp writes loses only the two empty section headers.
#
# NOTE: core/watcher/oslo-config-generator/watcher.conf is not staged. It is the
# input that produced watcher.conf.sample and is kept in the repo for the next
# release hop; the image has no use for it.
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(WATCHER_CONF_DIR)
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(WATCHER_APP_DIR)
	$(Q)chroot $(ROOTDIR) install -d -m 750 $(WATCHER_LOG_DIR)
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(WATCHER_RUN_DIR)
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/watcher/watcher.conf.sample .$(WATCHER_CONF_DIR)/watcher.conf
	$(Q)# install systemd unit files
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/watcher/openstack-watcher-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/watcher/openstack-watcher-applier.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/watcher/openstack-watcher-decision-engine.service ./lib/systemd/system

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chmod 0640 $(WATCHER_CONF_DIR)/watcher.conf
	$(Q)chroot $(ROOTDIR) chown watcher:watcher $(WATCHER_CONF_DIR) $(WATCHER_CONF_DIR)/watcher.conf
	$(Q)chroot $(ROOTDIR) chown watcher:watcher $(WATCHER_APP_DIR) $(WATCHER_LOG_DIR) $(WATCHER_RUN_DIR)

rootfs_install::
	# configuration changes
	$(Q)cp -f $(ROOTDIR)$(WATCHER_CONF_DIR)/watcher.conf $(ROOTDIR)$(WATCHER_CONF_DIR)/watcher.conf.def
	$(Q)chroot $(ROOTDIR) chown root:root $(WATCHER_CONF_DIR)/watcher.conf.def
	$(Q)chroot $(ROOTDIR) chmod 0640 $(WATCHER_CONF_DIR)/watcher.conf.def

rootfs_install::
	$(Q)set -e; for p in $$(find $(WATCHER_PATCHDIR) -name '*.py.patch' 2>/dev/null | sort); do \
		rel=$${p#$(WATCHER_PATCHDIR)/}; tgt=$(WATCHER_SRCDIR)/$${rel%.patch}; \
		if patch --dry-run --reverse --force "$$tgt" < "$$p" >/dev/null 2>&1; then \
			echo "  PATCH $${rel%.patch} (already applied)"; continue; \
		fi; \
		echo "  PATCH $${rel%.patch}"; \
		patch --forward --no-backup-if-mismatch -r - "$$tgt" < "$$p" \
			|| { echo "watcher: failed to apply $$p to $$tgt" >&2; exit 1; }; \
	done
	$(Q)cd $(WATCHER_PATCHDIR) && find . -type f ! -name '*.patch' ! -name '*.orig' \
		! -name '*.pyc' ! -path '*/__pycache__/*' | \
		while read f; do install -D -m 644 "$$f" $(WATCHER_SRCDIR)/"$$f"; done
	$(Q)# Register the CubeCOS allocation_balance strategy entry point (idempotent).
	$(Q)# pip installs a wheel, so the metadata directory is .dist-info; the
	$(Q)# python_watcher-*.egg-info the yoga rpm carried does not exist in the venv.
	$(Q)ep=$(WATCHER_SRCDIR)/python_watcher-$(WATCHER_VER).dist-info/entry_points.txt; \
		[ -f "$$ep" ] || { echo "watcher: $$ep not found, cannot register allocation_balance" >&2; exit 1; }; \
		grep -q '^allocation_balance =' "$$ep" || \
			sed -i '/^\[watcher_strategies\]/a allocation_balance = watcher.decision_engine.strategy.strategies.allocation_balance:AllocationBalance' "$$ep"
