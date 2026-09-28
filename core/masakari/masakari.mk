# Cube SDK
# masakari installation

MASAKARI_CONF_DIR := /etc/masakari
MASAKARI_MONITORS_CONF_DIR := /etc/masakarimonitors
MASAKARI_APP_DIR := /var/lib/masakari
MASAKARI_LOG_DIR := /var/log/masakari
MASAKARI_RUN_DIR := /var/run/masakari

# The patch pairs were split across two venvs between #639 and #636: masakari and
# masakari-monitors went to caracal, masakaridashboard could not because it is a
# horizon plugin and horizon was still antelope's. #636 moved horizon, so the
# dashboard patch rejoined the others under caracal_patch/ and antelope_patch/ went.
#
# The epoxy hop splits them the same way again. masakari and masakari-monitors move to
# the epoxy venv, so their five and three pairs are epoxy_patch/ and apply to that
# venv's site-packages; masakaridashboard stays with the served horizon, which is
# still the caracal venv's, so its pair stays caracal_patch/. The loop at the bottom
# runs once per venv.
#
# The dashboard patch matters -- upstream sets default_panel = 'default', a panel whose
# urls.py has no index, so an unpatched masakaridashboard makes the sidebar raise
# NoReverseMatch and every page 500s. Upstream has not fixed it at 10.0.0, so the patch
# was re-derived against that release rather than moved: 10.0.0 adds 'vmoves' to the
# panels tuple two lines above the change and renames ugettext_lazy to gettext_lazy, so
# the 8.0.0 hunk's context no longer matches.
MASAKARI_SRCDIR := $(ROOTDIR)$(NEXT_OPENSTACK_HOME_DIR)/lib/python$(NEXT_PYTHON_VER)/site-packages
MASAKARI_PATCHDIR := $(COREDIR)/masakari/$(NEXT_OPENSTACK_RELEASE)_patch
MASAKARI_DASHBOARD_SRCDIR := $(ROOTDIR)$(OPENSTACK_HOME_DIR)/lib/python$(PYTHON_VER)/site-packages
MASAKARI_DASHBOARD_PATCHDIR := $(COREDIR)/masakari/$(OPENSTACK_RELEASE)_patch

# masakari common
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(MASAKARI_CONF_DIR) $(MASAKARI_MONITORS_CONF_DIR) $(MASAKARI_APP_DIR) $(MASAKARI_LOG_DIR) $(MASAKARI_RUN_DIR)
	$(Q)chroot $(ROOTDIR) chown masakari:masakari $(MASAKARI_CONF_DIR) $(MASAKARI_MONITORS_CONF_DIR) $(MASAKARI_APP_DIR) $(MASAKARI_LOG_DIR) $(MASAKARI_RUN_DIR)

# install masakari and masakari-monitors into the epoxy venv
#
# https://releases.openstack.org/epoxy/index.html#epoxy-masakari -- 19.1.0 and 19.0.0
# are the newest 2025.1 releases, the same "last numeric revision of the series" rule
# #639 used to land on 17.0.0 / 17.0.1. 19.1.0 adds only upstream's masakari.wsgi
# application module over 19.0.0. masakari-monitors' stable/2025.1 carries one commit
# past 19.0.0, unreleased and for the consul host monitor driver, which is not the one
# this deployment runs.
#
# Both services run out of the epoxy venv, not the caracal one they shared with the
# 2024.1 services still there. They cannot be bumped in place: 19.x requires
# oslo.policy>=4.5.0, which os-caracal-pip-upper-constraints.txt holds at 4.3.0 for
# octavia and the other 2024.1 services. So they move into $(NEXT_OPENSTACK_HOME_DIR)
# together, the same shape as their caracal hop (#639), one release on, after
# keystone, glance, cinder, nova/placement, neutron, barbican, cyborg, designate, heat,
# ironic and manila. masakari-monitors' three carried patches apply to 19.0.0
# unchanged, and of masakari's five only conf/engine.py's upstream file moved, by help
# text outside the hunk.
#
# Four packages have to be named because neither requirements.txt asks for them and
# pip will not pull them in transitively:
# libvirt-python: masakarimonitors imports libvirt directly
#   (instancemonitor/instance.py). Upstream removed it from requirements.txt in
#   12.0.0 ("Note to packagers"), and when nova left the antelope venv without it,
#   instancemonitor crash-looped on ModuleNotFoundError (#1347). core/nova/nova.mk
#   names it for this venv as well, and both constraints files pin ===11.10.0, so the
#   binding version does not change with the venv.
# PyMySQL: config_masakari.cpp writes a mysql+pymysql:// connection
# oslo.messaging[kafka]: config_masakari.cpp points the notification transport at
#   kafka://
# python-memcached: config_masakari.cpp writes [keystone_authtoken] memcached_servers,
#   which makes keystonemiddleware import memcache on its first token validation
# All four happen to be in this venv already, but a dependency nothing asks for is one
# that disappears silently.
#
# The /usr/bin/masakari-* links follow the services: the units, config_masakari.cpp
# and hex_sdk's migrate_masakari_db all reach them through those.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(NEXT_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		masakari==19.1.0 \
		masakari-monitors==19.0.0 \
		libvirt-python \
		PyMySQL \
		\"oslo.messaging[kafka]\" \
		python-memcached"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries -- masakari's four console_scripts plus its one wsgi_script,
	$(Q)# and masakarimonitors' four; 2025.1 declares the same nine as 2024.1. The
	$(Q)# units keep naming /usr/bin/*, so the retarget here is the whole of their move.
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/masakari-api /usr/bin/masakari-api
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/masakari-engine /usr/bin/masakari-engine
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/masakari-manage /usr/bin/masakari-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/masakari-status /usr/bin/masakari-status
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/masakari-wsgi /usr/bin/masakari-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/masakari-hostmonitor /usr/bin/masakari-hostmonitor
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/masakari-instancemonitor /usr/bin/masakari-instancemonitor
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/masakari-introspectiveinstancemonitor /usr/bin/masakari-introspectiveinstancemonitor
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/masakari-processmonitor /usr/bin/masakari-processmonitor

# the osc plugin and the dashboard
#
# python-masakariclient owns the "ha" osc plugin entry point ("openstack segment ...",
# which hex_sdk's os_masakari_maintenance_hosts drives), and a stevedore entry point is
# only visible to the interpreter it was installed under, so the plugin has to sit next
# to /usr/bin/openstack. That held it in the antelope venv from #639 until #636 moved
# the cli here. The epoxy hop moves only the services: /usr/bin/openstack is still the
# caracal venv's, so the client stays here while masakari runs from the epoxy venv, the
# same split heat's (#661) and manila's (#664) hops made. It talks HTTP and the
# masakari API still tops out at microversion 1.3, so the caracal client drives
# 19.1.0 as it drove 17.0.0. It owns no console script of its own, so nothing needs
# relinking. The constraints file decides its version, the way core/designate does it
# for python-designateclient -- it is not a branch-name clone.
#
# masakari-dashboard is a horizon plugin: core/horizon/horizon.mk copies its enabled
# panels out of $(HORIZON_VENV_SP), which is the site-packages of whichever venv
# horizon runs in, so the dashboard goes where horizon goes. #636 took horizon to
# caracal, so the panel is a caracal-venv install now. 10.0.0 is the caracal release --
# https://releases.openstack.org/caracal/index.html#caracal-masakari-dashboard. Horizon
# plugins are not in the upper-constraints (that file only covers libraries), so the
# pin is explicit; it replaces a $(OPS_GITHUB_BRANCH_02) clone, whose version was
# whatever the branch tip was on build day. It stays the caracal release when the
# services move to epoxy, for the same reason: the served horizon is still the caracal
# venv's.
#
# 10.0.0 brings the vmoves panel with it. The API behind it has been there since
# masakari 17.0.0 (#639); only the panel was missing, and this is what supplies it.
MASAKARI_DASHBOARD_VER := 10.0.0

rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-masakariclient
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		masakari-dashboard==$(MASAKARI_DASHBOARD_VER)
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# install custom files
# for masakari
rootfs_install::
	$(Q)# api-paste.ini comes out of the venv prefix rather than a checked-in copy or
	$(Q)# the git checkout pip replaced: masakari's setup.cfg data_files puts it
	$(Q)# there, and taking it from the install means it tracks the pinned version
	$(Q)# instead of going stale silently. cinder.mk, glance.mk and designate.mk do
	$(Q)# the same. It is byte-identical between 17.0.0 and 19.1.0, so the hop moves
	$(Q)# only which venv prefix it is read from.
	$(Q)chroot $(ROOTDIR) cp -f $(NEXT_OPENSTACK_HOME_DIR)/etc/masakari/api-paste.ini $(MASAKARI_CONF_DIR)/api-paste.ini
	$(Q)# -f: treat the destination as the full target path. Without it the install
	$(Q)# script takes masakari.conf.def for a directory and drops the sample inside
	$(Q)# it, so config_masakari.cpp's LoadConfig() finds nothing to read.
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/masakari/masakari.conf.sample .$(MASAKARI_CONF_DIR)/masakari.conf.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari_sudoers ./etc/sudoers.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-engine.service ./lib/systemd/system

# for masakari-monitors
rootfs_install::
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/masakari/masakarimonitors.conf.sample .$(MASAKARI_MONITORS_CONF_DIR)/masakarimonitors.conf.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/process_list.yaml $(MASAKARI_MONITORS_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-instancemonitor.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-processmonitor.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-hostmonitor.service ./lib/systemd/system
	$(Q)# gate the monitors on the planned-maintenance marker (see cube-planned-maintenance.conf)
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/masakari-instancemonitor.service.d /etc/systemd/system/masakari-processmonitor.service.d /etc/systemd/system/masakari-hostmonitor.service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/main/cube-planned-maintenance.conf ./etc/systemd/system/masakari-instancemonitor.service.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/main/cube-planned-maintenance.conf ./etc/systemd/system/masakari-processmonitor.service.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/main/cube-planned-maintenance.conf ./etc/systemd/system/masakari-hostmonitor.service.d/

# NOTE: core/masakari/oslo-config-generator/*.conf are not staged. They are the inputs
# that produced the two .conf.sample files above and are kept in the repo for the next
# release hop; the image has no use for them.

# Apply the reviewable unified diffs to the pip-installed masakari sources.
# Each patch sits at <PATCHDIR>/<rel>.py.patch and targets <SRCDIR>/<rel>.py;
# a <rel>.py.orig alongside it is the pristine upstream file, kept only for
# review. --forward makes re-runs idempotent; a failed hunk aborts the build
# (so upstream drift is caught at build time, not shipped silently). One loop per
# venv -- see the note on the patch dirs at the top.
rootfs_install::
	$(Q)set -e; for p in $$(find $(MASAKARI_PATCHDIR) -name '*.py.patch' 2>/dev/null | sort); do \
		rel=$${p#$(MASAKARI_PATCHDIR)/}; tgt=$(MASAKARI_SRCDIR)/$${rel%.patch}; \
		echo "  PATCH $${rel%.patch}"; \
		patch --forward --no-backup-if-mismatch -r - "$$tgt" < "$$p" \
			|| { echo "masakari: failed to apply $$p to $$tgt" >&2; exit 1; }; \
	done
	$(Q)set -e; for p in $$(find $(MASAKARI_DASHBOARD_PATCHDIR) -name '*.py.patch' 2>/dev/null | sort); do \
		rel=$${p#$(MASAKARI_DASHBOARD_PATCHDIR)/}; tgt=$(MASAKARI_DASHBOARD_SRCDIR)/$${rel%.patch}; \
		echo "  PATCH $${rel%.patch}"; \
		patch --forward --no-backup-if-mismatch -r - "$$tgt" < "$$p" \
			|| { echo "masakari: failed to apply $$p to $$tgt" >&2; exit 1; }; \
	done
