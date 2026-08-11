# Cube SDK
# masakari installation

MASAKARI_CONF_DIR := /etc/masakari
MASAKARI_MONITORS_CONF_DIR := /etc/masakarimonitors
MASAKARI_APP_DIR := /var/lib/masakari
MASAKARI_LOG_DIR := /var/log/masakari
MASAKARI_RUN_DIR := /var/run/masakari

# masakari, masakarimonitors and masakaridashboard are all patched inside the
# antelope venv now: #609 moved horizon there, so the dashboard no longer has a
# python 3.9 copy and the per-tree patch pairs collapse back to one directory.
# The dashboard patch matters -- upstream sets default_panel = 'default', a panel
# whose urls.py has no index, so an unpatched masakaridashboard makes the sidebar
# raise NoReverseMatch and every page 500s.
MASAKARI_SRCDIR := $(ROOTDIR)$(OPENSTACK_HOME_DIR)/lib/python$(PYTHON_VER)/site-packages
MASAKARI_PATCHDIR := $(COREDIR)/masakari/$(OPENSTACK_RELEASE)_patch

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/masakari
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/masakari

# masakari common
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(MASAKARI_CONF_DIR) $(MASAKARI_MONITORS_CONF_DIR) $(MASAKARI_APP_DIR) $(MASAKARI_LOG_DIR) $(MASAKARI_RUN_DIR)
	$(Q)chroot $(ROOTDIR) chown masakari:masakari $(MASAKARI_CONF_DIR) $(MASAKARI_MONITORS_CONF_DIR) $(MASAKARI_APP_DIR) $(MASAKARI_LOG_DIR) $(MASAKARI_RUN_DIR)

# masakari-api and masakari-engine
MASAKARI_REPO_URL := https://github.com/openstack/masakari.git
# The python 3.9 copy is gone. It only existed so horizon's dump_default_policies
# could resolve the "masakari" oslo.policy.policies entry point; that command runs
# under the venv python now (#609), where the venv's own masakari provides it.

# install masakari-api and masakari-engine inside the python 3.10 virtual environment
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(OPS_GITHUB_BRANCH_02) --depth 1 $(MASAKARI_REPO_URL) /tmp/masakari/masakari
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		-r /tmp/masakari/masakari/requirements.txt
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/masakari/masakari && \
		/opt/openstack-antelope/bin/python setup.py install"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/masakari-api /usr/bin/masakari-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/masakari-engine /usr/bin/masakari-engine
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/masakari-manage /usr/bin/masakari-manage
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/masakari-status /usr/bin/masakari-status
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/masakari-wsgi /usr/bin/masakari-wsgi

rootfs_install::
	$(Q)cp -f $(ROOTDIR)/tmp/masakari/masakari/etc/masakari/api-paste.ini $(ROOTDIR)$(MASAKARI_CONF_DIR)/api-paste.ini
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari.conf.def .$(MASAKARI_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari_sudoers ./etc/sudoers.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-engine.service ./lib/systemd/system

# masakari-monitors process/instance/host
MASAKARI_MONITORS_REPO_URL := https://github.com/openstack/masakari-monitors.git

# install masakari-monitors process/instance/host inside the python 3.10 virtual environment
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(OPS_GITHUB_BRANCH_02) --depth 1 $(MASAKARI_MONITORS_REPO_URL) /tmp/masakari/masakari-monitors
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		-r /tmp/masakari/masakari-monitors/requirements.txt
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/masakari/masakari-monitors && \
		/opt/openstack-antelope/bin/python setup.py install"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/masakari-hostmonitor /usr/bin/masakari-hostmonitor
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/masakari-instancemonitor /usr/bin/masakari-instancemonitor
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/masakari-introspectiveinstancemonitor /usr/bin/masakari-introspectiveinstancemonitor
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/masakari-processmonitor /usr/bin/masakari-processmonitor

rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakarimonitors.conf.def $(MASAKARI_MONITORS_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/process_list.yaml $(MASAKARI_MONITORS_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-instancemonitor.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-processmonitor.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/masakari/masakari-hostmonitor.service ./lib/systemd/system

# masakari command line plugin
#
# The venv clone below is the only install. It used to be paired with a
# ROOTFS_PIP_DL_FROM entry that put a second copy in the system python 3.9, so the
# "ha" osc plugin would resolve for /usr/bin/openstack while that was still
# `#!/usr/bin/python3`; the cli moved into the venv, so the 3.9 copy is gone. It
# owned no console script -- masakariclient ships only the osc plugin -- so nothing
# needs relinking.
MASAKARI_CLI_REPO_URL := https://github.com/openstack/python-masakariclient.git

# install masakari command line plugin inside the python 3.10 virtual environment
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(OPS_GITHUB_BRANCH_02) --depth 1 $(MASAKARI_CLI_REPO_URL) /tmp/masakari/python-masakariclient
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		-r /tmp/masakari/python-masakariclient/requirements.txt
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/masakari/python-masakariclient && \
		/opt/openstack-antelope/bin/python setup.py install"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# masakari web ui plugin
MASAKARI_DASHBOARD_REPO_URL := https://github.com/openstack/masakari-dashboard.git

# install masakari web ui plugin inside the python 3.10 virtual environment
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(OPS_GITHUB_BRANCH_02) --depth 1 $(MASAKARI_DASHBOARD_REPO_URL) /tmp/masakari/masakari-dashboard
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		-r /tmp/masakari/masakari-dashboard/requirements.txt
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/masakari/masakari-dashboard && \
		/opt/openstack-antelope/bin/python setup.py install"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# Apply the reviewable unified diffs to the pip-installed masakari sources.
# Each patch sits at <PATCHDIR>/<rel>.py.patch and targets <SRCDIR>/<rel>.py;
# a <rel>.py.orig alongside it is the pristine upstream file, kept only for
# review. --forward makes re-runs idempotent; a failed hunk aborts the build
# (so upstream drift is caught at build time, not shipped silently).
rootfs_install::
	$(Q)set -e; for p in $$(find $(MASAKARI_PATCHDIR) -name '*.py.patch' 2>/dev/null | sort); do \
		rel=$${p#$(MASAKARI_PATCHDIR)/}; tgt=$(MASAKARI_SRCDIR)/$${rel%.patch}; \
		echo "  PATCH $${rel%.patch}"; \
		patch --forward --no-backup-if-mismatch -r - "$$tgt" < "$$p" \
			|| { echo "masakari: failed to apply $$p to $$tgt" >&2; exit 1; }; \
	done

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/masakari
