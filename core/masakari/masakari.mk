# Cube SDK
# masakari installation

MASAKARI_CONF_DIR := /etc/masakari
MASAKARI_MONITORS_CONF_DIR := /etc/masakarimonitors
MASAKARI_APP_DIR := /var/lib/masakari
MASAKARI_LOG_DIR := /var/log/masakari
MASAKARI_RUN_DIR := /var/run/masakari

# The patch pairs split across two venvs from #639 on. masakari and
# masakari-monitors are in the caracal venv; masakaridashboard is not, because it is a
# horizon plugin and horizon is still antelope's. The dashboard patch matters --
# upstream sets default_panel = 'default', a panel whose urls.py has no index, so an
# unpatched masakaridashboard makes the sidebar raise NoReverseMatch and every page
# 500s. It rejoins the others under caracal_patch/ when horizon hops (#636), and
# antelope_patch/ goes with it.
MASAKARI_CARACAL_SRCDIR := $(ROOTDIR)$(CARACAL_OPENSTACK_HOME_DIR)/lib/python$(CARACAL_PYTHON_VER)/site-packages
MASAKARI_CARACAL_PATCHDIR := $(COREDIR)/masakari/$(CARACAL_OPENSTACK_RELEASE)_patch
MASAKARI_ANTELOPE_SRCDIR := $(ROOTDIR)$(OPENSTACK_HOME_DIR)/lib/python$(PYTHON_VER)/site-packages
MASAKARI_ANTELOPE_PATCHDIR := $(COREDIR)/masakari/$(OPENSTACK_RELEASE)_patch

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/masakari
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/masakari

# masakari common
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(MASAKARI_CONF_DIR) $(MASAKARI_MONITORS_CONF_DIR) $(MASAKARI_APP_DIR) $(MASAKARI_LOG_DIR) $(MASAKARI_RUN_DIR)
	$(Q)chroot $(ROOTDIR) chown masakari:masakari $(MASAKARI_CONF_DIR) $(MASAKARI_MONITORS_CONF_DIR) $(MASAKARI_APP_DIR) $(MASAKARI_LOG_DIR) $(MASAKARI_RUN_DIR)

# install masakari and masakari-monitors into the caracal venv
#
# 17.0.0 and 17.0.1 are the 2024.1 releases, verified as the newest tags that are
# ancestors of upstream's unmaintained/2024.1. Both services move into
# $(CARACAL_OPENSTACK_HOME_DIR) together: masakarimonitors is the only consumer of the
# antelope venv's libvirt-python and the only thing still holding the
# /usr/bin/privsep-helper symlink open, so leaving it behind would carry two
# TEMPORARY arrangements into the next hop for no gain -- its three carried patches
# apply to 17.0.1 unchanged.
#
# This also converts the install from `git clone` + `setup.py install` to a pinned pip
# install, which is what every caracal hop before it does -- there is no .mk in this
# tree that still reads $(CARACAL_OPS_GITHUB_BRANCH_0*), and stable/2024.1 does not
# exist on the github mirror anyway. The clone was pinned to nothing but a branch
# name, so the same build inputs produced a different masakari on different days.
#
# Three packages have to be named because neither requirements.txt asks for them and
# pip will not pull them in transitively:
# libvirt-python: masakarimonitors imports libvirt directly
#   (instancemonitor/instance.py). Upstream removed it from requirements.txt in
#   12.0.0 ("Note to packagers"), and it used to arrive here only because nova shared
#   the antelope venv; when nova left, instancemonitor crash-looped on
#   ModuleNotFoundError (#1347). Both constraints files pin ===11.10.0, so the
#   binding version does not change with the venv.
# PyMySQL: config_masakari.cpp:194 writes a mysql+pymysql:// connection
# oslo.messaging[kafka]: config_masakari.cpp:231 points the notification transport at
#   kafka://
# The last two are in this venv already (keystone.mk installs them), but a dependency
# nothing asks for is one that disappears silently.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(CARACAL_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		masakari==17.0.0 \
		masakari-monitors==17.0.1 \
		libvirt-python \
		PyMySQL \
		\"oslo.messaging[kafka]\""
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries -- masakari's four console_scripts plus its one wsgi_script,
	$(Q)# and masakarimonitors' four. The units keep naming /usr/bin/*, so the
	$(Q)# retarget here is the whole of their move.
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/masakari-api /usr/bin/masakari-api
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/masakari-engine /usr/bin/masakari-engine
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/masakari-manage /usr/bin/masakari-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/masakari-status /usr/bin/masakari-status
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/masakari-wsgi /usr/bin/masakari-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/masakari-hostmonitor /usr/bin/masakari-hostmonitor
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/masakari-instancemonitor /usr/bin/masakari-instancemonitor
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/masakari-introspectiveinstancemonitor /usr/bin/masakari-introspectiveinstancemonitor
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/masakari-processmonitor /usr/bin/masakari-processmonitor

# the osc plugin and the dashboard stay in the antelope venv -- TEMPORARY
#
# python-masakariclient owns the "ha" osc plugin entry point ("openstack segment ...",
# which hex_sdk's os_masakari_maintenance_hosts drives), and a stevedore entry point is
# only visible to the interpreter it was installed under. /usr/bin/openstack is the
# antelope venv's, so the plugin has to stay next to it. It owns no console script of
# its own, so nothing needs relinking. It is now a pinned pip install like the rest --
# the antelope constraints file decides the version, the way core/designate does it for
# python-designateclient -- rather than a branch-name clone.
#
# masakari-dashboard is a horizon plugin, and horizon itself is still the antelope
# venv's (core/horizon/horizon.mk). $(HORIZON_VENV_SP) is that venv's site-packages,
# and that is where horizon's collectstatic collects the panels from, so the dashboard
# cannot move ahead of horizon. It is left on its git checkout at
# $(OPS_GITHUB_BRANCH_02) deliberately: converting it to pip would change which
# dashboard version lands, and this story is not the place to do that. That is also
# why the caracal vmoves panel does not appear -- the API is there at 17.0.0, the
# panel that drives it is not.
#
# Both go once horizon reaches the caracal venv (#636).
MASAKARI_DASHBOARD_REPO_URL := https://github.com/openstack/masakari-dashboard.git

rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-masakariclient
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(OPS_GITHUB_BRANCH_02) --depth 1 $(MASAKARI_DASHBOARD_REPO_URL) /tmp/masakari/masakari-dashboard
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		-r /tmp/masakari/masakari-dashboard/requirements.txt
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/masakari/masakari-dashboard && \
		$(OPENSTACK_HOME_DIR)/bin/python setup.py install"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# install custom files
# for masakari
rootfs_install::
	$(Q)# api-paste.ini comes out of the venv prefix rather than a checked-in copy or
	$(Q)# the git checkout pip replaced: masakari's setup.cfg data_files puts it
	$(Q)# there, and taking it from the install means it tracks the pinned version
	$(Q)# instead of going stale silently. cinder.mk, glance.mk and designate.mk do
	$(Q)# the same.
	$(Q)chroot $(ROOTDIR) cp -f $(CARACAL_OPENSTACK_HOME_DIR)/etc/masakari/api-paste.ini $(MASAKARI_CONF_DIR)/api-paste.ini
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
# (so upstream drift is caught at build time, not shipped silently).
rootfs_install::
	$(Q)set -e; for p in $$(find $(MASAKARI_CARACAL_PATCHDIR) -name '*.py.patch' 2>/dev/null | sort); do \
		rel=$${p#$(MASAKARI_CARACAL_PATCHDIR)/}; tgt=$(MASAKARI_CARACAL_SRCDIR)/$${rel%.patch}; \
		echo "  PATCH $${rel%.patch}"; \
		patch --forward --no-backup-if-mismatch -r - "$$tgt" < "$$p" \
			|| { echo "masakari: failed to apply $$p to $$tgt" >&2; exit 1; }; \
	done
	$(Q)set -e; for p in $$(find $(MASAKARI_ANTELOPE_PATCHDIR) -name '*.py.patch' 2>/dev/null | sort); do \
		rel=$${p#$(MASAKARI_ANTELOPE_PATCHDIR)/}; tgt=$(MASAKARI_ANTELOPE_SRCDIR)/$${rel%.patch}; \
		echo "  PATCH $${rel%.patch}"; \
		patch --forward --no-backup-if-mismatch -r - "$$tgt" < "$$p" \
			|| { echo "masakari: failed to apply $$p to $$tgt" >&2; exit 1; }; \
	done

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/masakari
