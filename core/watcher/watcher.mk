# Cube SDK
# watcher installation

# https://releases.openstack.org/caracal/index.html#caracal-watcher
WATCHER_VER := 12.1.0

WATCHER_CONF_DIR := /etc/watcher
WATCHER_APP_DIR := /var/cache/watcher
WATCHER_LOG_DIR := /var/log/watcher
WATCHER_RUN_DIR := /var/run/watcher

# The service moves into the caracal venv; the osc plugin and the dashboard do not follow
# it -- see the second install block. WATCHER_SRCDIR deliberately stops at site-packages
# instead of descending into watcher/ the way cyborg.mk, nova.mk and neutron.mk do,
# because the entry point registration at the bottom of this file reaches the dist-info
# directory through it. The patch tree carries its own leading watcher/ to compensate.
WATCHER_SRCDIR := $(ROOTDIR)$(CARACAL_OPENSTACK_HOME_DIR)/lib/python$(CARACAL_PYTHON_VER)/site-packages
WATCHER_PATCHDIR := $(COREDIR)/watcher/$(CARACAL_OPENSTACK_RELEASE)_patch

# https://releases.openstack.org/caracal/index.html#caracal-watcher-dashboard
# Horizon plugins are not in the upper-constraints (that file only covers libraries),
# so the pin is explicit. This used to be a git clone of the 2023.1-eol *tag*, because
# watcher-dashboard publishes neither stable/2023.1 nor unmaintained/2023.1 -- both
# branches were deleted at EOL, so there was no branch for installpip's fallback chain
# to resolve. #636 moved the panel to the caracal release, which is on PyPI as a wheel,
# and the tag hack goes with it.
WATCHER_DASHBOARD_VER := 11.0.0

# install watcher inside the python 3.11 caracal virtual environment
#
# 12.1.0 is the 2024.1 release, verified as the newest tag that is an ancestor of
# upstream's unmaintained/2024.1: that branch's head, the 2024.1-eom tag and 12.1.0 are
# all commit 8f8d537. The service joins keystone, glance, cinder, nova with placement,
# neutron, manila, octavia, barbican, cyborg and designate in
# $(CARACAL_OPENSTACK_HOME_DIR).
#
# Nothing about the packaging changes here -- watcher was already a pinned pip install
# when it lived in the antelope venv, so this hop only moves it. The RDO rpms
# openstack-watcher-{api,applier,decision-engine,common} and python3-watcher were
# dropped at that earlier hop, not this one. openstack-watcher.spec has no
# watcher-dist.conf, no rootwrap and no sudoers, and it deletes the wheel's whole
# /usr/etc tree -- the only data_files there are the config sample, a README and the
# two generator inputs -- so unlike heat, ironic and manila there is nothing to
# relocate out of the venv prefix. The watcher user and group come from
# core/heavyfs/account/centos9 statically, so shadow-utils is not needed either.
#
# requirements.txt differs from 10.0.0's by exactly one line, oslo.messaging raised to
# >=14.1.0 for the messaging.RPCClient -> messaging.get_rpc_client rename, and
# os-caracal-pip-upper-constraints.txt already pins every one of them.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(CARACAL_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			python-watcher==$(WATCHER_VER)"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries. This is exactly the set the rpms put in /usr/bin, which is
	$(Q)# every console_script watcher declares plus the one wsgi_script. 12.1.0's
	$(Q)# setup.cfg [entry_points] is byte-identical to 10.0.0's, so the set is unchanged.
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/watcher-api /usr/bin/watcher-api
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/watcher-api-wsgi /usr/bin/watcher-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/watcher-applier /usr/bin/watcher-applier
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/watcher-db-manage /usr/bin/watcher-db-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/watcher-decision-engine /usr/bin/watcher-decision-engine
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/watcher-status /usr/bin/watcher-status
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/watcher-sync /usr/bin/watcher-sync

# the osc plugin and the web ui plugin stay in the antelope venv -- TEMPORARY
#
# python-watcherclient owns the "optimize" osc plugin entry point, which hex_sdk's
# health_watcher_check() drives as `openstack optimize service list`. A stevedore entry
# point is only visible to the interpreter it was installed under, and /usr/bin/openstack
# is the antelope venv's (core/heavyfs/Makefile), so the plugin has to stay next to it or
# the health check cannot run its query at all. #632, #633 and #634 hit the same
# constraint for python-barbicanclient, python-cyborgclient and python-designateclient.
#
# The client can stay a release behind because watcher's REST API did not move: not one
# file under watcher/api/ differs between 10.0.0 and unmaintained/2024.1, so the 4.1.0
# the antelope constraint resolves still speaks to 12.1.0.
#
# It is named explicitly rather than left to watcher-dashboard's requirements.txt, which
# also asks for it. designate.mk carries the story: a client that arrives only as a side
# effect of some other install disappears silently the day that install moves, and the
# symptom is `cluster check` reporting the service NG while every unit is active. No
# version is named, the same way cyborg.mk does not name one: the antelope constraints
# file already carries python-watcherclient (4.1.0), so a version here could only drift
# from it.
#
# watcher-dashboard is a horizon plugin: core/horizon/horizon.mk copies its enabled
# panels out of $(HORIZON_VENV_SP), which is the site-packages of whichever venv
# horizon runs in, so the dashboard goes where horizon goes. #636 took horizon to
# caracal, so the panel is a caracal-venv install now.
#
# The osc plugin goes once /usr/bin/openstack is the caracal venv's (#636).
#
# /usr/bin/watcher is the client's own cli. It used to come from the system python 3.9
# install as /usr/local/bin/watcher -- /usr/bin held only the watcher-* service scripts
# linked above -- and since /usr/local/bin precedes /usr/bin in the PATH hex_sdk sets,
# the replacement is this symlink, the same shape core/monasca uses. It points at the
# antelope venv because that is where the client is, not where the service is.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) $(CARACAL_OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-watcherclient
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) $(CARACAL_OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		watcher-dashboard==$(WATCHER_DASHBOARD_VER)
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/watcher /usr/bin/watcher

# install system directories and files
#
# watcher.conf.sample is generated and checked in so builds stay reproducible and
# config diffs remain reviewable. It is oslo-config-generator run over
# oslo-config-generator/watcher.conf, which is still byte-identical to upstream's
# copy -- the file did not change between the 10.0.0 tag and unmaintained/2024.1 --
# with the same two adjustments the RDO spec also makes or needs:
#   - #pybasedir is stripped; its default is the build path and is meaningless here.
#   - watcher.objects.register_all() is called before the generator, otherwise
#     stevedore fails to load the "taskflow" opts entry point ("module
#     watcher.objects has no attribute action_plan") and the sample silently loses
#     the [watcher_workflow_engines.taskflow] section.
# Regenerated against 12.1.0 the sample gains one section, [maas_client], for the
# datasource upstream added, and loses none: 45 sections become 46. That is the only
# structural change, and it changes nothing at runtime, because every option in a
# generator sample is commented out -- the file carries zero uncommented keys before
# and after, so LoadConfig() reads the same empty sections it always did.
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
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/watcher/metric_map.yaml .$(WATCHER_CONF_DIR)/metric_map.yaml
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
	$(Q)[ -d $(WATCHER_PATCHDIR) ] && cp -rf $(WATCHER_PATCHDIR)/* $(WATCHER_SRCDIR)/ || /bin/true
	$(Q)# Register the CubeCOS allocation_balance strategy entry point (idempotent).
	$(Q)# pip installs a wheel, so the metadata directory is .dist-info; the
	$(Q)# python_watcher-*.egg-info the yoga rpm carried does not exist in the venv.
	$(Q)ep=$(WATCHER_SRCDIR)/python_watcher-$(WATCHER_VER).dist-info/entry_points.txt; \
		[ -f "$$ep" ] || { echo "watcher: $$ep not found, cannot register allocation_balance" >&2; exit 1; }; \
		grep -q '^allocation_balance =' "$$ep" || \
			sed -i '/^\[watcher_strategies\]/a allocation_balance = watcher.decision_engine.strategy.strategies.allocation_balance:AllocationBalance' "$$ep"
