# Cube SDK
# masakari installation

MASAKARI_CONF_DIR := /etc/masakari
MASAKARI_MONITORS_CONF_DIR := /etc/masakarimonitors
MASAKARI_APP_DIR := /var/lib/masakari
MASAKARI_LOG_DIR := /var/log/masakari
MASAKARI_RUN_DIR := /var/run/masakari

# masakari and masakarimonitors are patched inside the antelope venv, but
# masakaridashboard is patched in the system python because horizon runs there.
# The python 3.9 masakari copy is deliberately left unpatched: it exists only so
# horizon's dump_default_policies can resolve the "masakari" oslo.policy.policies
# entry point, and no service runs out of it. See the install rule below.
MASAKARI_SRCDIR := $(ROOTDIR)/opt/openstack-antelope/lib/python3.10/site-packages/masakari
MASAKARI_PATCHDIR := $(COREDIR)/masakari/$(NEXT_OPENSTACK_RELEASE)_patch/masakari
MASAKARI_MONITORS_SRCDIR := $(ROOTDIR)/opt/openstack-antelope/lib/python3.10/site-packages/masakarimonitors
MASAKARI_MONITORS_PATCHDIR := $(COREDIR)/masakari/$(NEXT_OPENSTACK_RELEASE)_patch/masakarimonitors
MASAKARI_DASHBOARD_SRCDIR := $(ROOTDIR)/usr/local/lib/python3.9/site-packages/masakaridashboard
MASAKARI_DASHBOARD_PATCHDIR := $(COREDIR)/masakari/$(NEXT_OPENSTACK_RELEASE)_patch/masakaridashboard

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
# FIXME: drop the installation in python 3.9 after wrapping up the whole upgrade of openstack.
# masakari owns the "masakari" oslo.policy.policies entry point, and horizon's
# dump_default_policies below runs under python 3.9. Without this the namespace
# is not found, that command exits 1 and the build fails.
ROOTFS_PIP_DL_FROM += $(MASAKARI_REPO_URL)

# install masakari-api and masakari-engine inside the python 3.10 virtual environment
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(NEXT_OPS_GITHUB_BRANCH_02) --depth 1 $(MASAKARI_REPO_URL) /tmp/masakari/masakari
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
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
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(NEXT_OPS_GITHUB_BRANCH_02) --depth 1 $(MASAKARI_MONITORS_REPO_URL) /tmp/masakari/masakari-monitors
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
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
MASAKARI_CLI_REPO_URL := https://github.com/openstack/python-masakariclient.git
# FIXME: drop the installation in python 3.9 after wrapping up the whole upgrade of openstack
ROOTFS_PIP_DL_FROM += $(MASAKARI_CLI_REPO_URL)

# install masakari command line plugin inside the python 3.10 virtual environment
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(NEXT_OPS_GITHUB_BRANCH_02) --depth 1 $(MASAKARI_CLI_REPO_URL) /tmp/masakari/python-masakariclient
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		-r /tmp/masakari/python-masakariclient/requirements.txt
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/masakari/python-masakariclient && \
		/opt/openstack-antelope/bin/python setup.py install"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# masakari web ui plugin
MASAKARI_DASHBOARD_REPO_URL := https://github.com/openstack/masakari-dashboard.git
# FIXME: drop the installation in python 3.9 after wrapping up the whole upgrade of openstack
ROOTFS_PIP_DL_FROM += $(MASAKARI_DASHBOARD_REPO_URL)

# install masakari web ui plugin inside the python 3.10 virtual environment
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(NEXT_OPS_GITHUB_BRANCH_02) --depth 1 $(MASAKARI_DASHBOARD_REPO_URL) /tmp/masakari/masakari-dashboard
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		-r /tmp/masakari/masakari-dashboard/requirements.txt
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/masakari/masakari-dashboard && \
		/opt/openstack-antelope/bin/python setup.py install"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# FIXME: need to update the Horizon panel path after upgrading Horizon
# rootfs_install::
# 	$(Q)cp -f $(ROOTDIR)/tmp/masakari/masakari-dashboard/masakaridashboard/local/enabled/_50_masakaridashboard.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
# 	$(Q)cp -f $(ROOTDIR)/tmp/masakari/masakari-dashboard/masakaridashboard/local/local_settings.d/_50_masakari.py $(ROOTDIR)/$(HORIZON_DIR)/local/local_settings.d/
# 	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/python /usr/share/openstack-dashboard/manage.py dump_default_policies --namespace masakari --output-file $(HORIZON_POLICY_DIR)/masakari.yaml 2>&1 > /dev/null

rootfs_install::
	$(Q)cp -f $(PIPS_DIR)/masakari-dashboard.git/masakaridashboard/local/enabled/_50_masakaridashboard.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
	$(Q)cp -f $(PIPS_DIR)/masakari-dashboard.git/masakaridashboard/local/local_settings.d/_50_masakari.py $(ROOTDIR)/$(HORIZON_DIR)/local/local_settings.d/
	$(Q)chroot $(ROOTDIR) python3 /usr/share/openstack-dashboard/manage.py dump_default_policies --namespace masakari --output-file $(HORIZON_POLICY_DIR)/masakari.yaml 2>&1 > /dev/null

# Apply the reviewable unified diffs to the pip-installed masakari sources.
# Each patch sits at <PATCHDIR>/<rel>.py.patch and targets <SRCDIR>/<rel>.py;
# a <rel>.py.orig alongside it is the pristine upstream file, kept only for
# review. --forward makes re-runs idempotent; a failed hunk aborts the build
# (so upstream drift is caught at build time, not shipped silently).
# One loop, one <patchdir>:<srcdir> pair per source tree, because the three
# trees do not share an interpreter yet.
MASAKARI_PATCH_PAIRS := \
	$(MASAKARI_PATCHDIR):$(MASAKARI_SRCDIR) \
	$(MASAKARI_MONITORS_PATCHDIR):$(MASAKARI_MONITORS_SRCDIR) \
	$(MASAKARI_DASHBOARD_PATCHDIR):$(MASAKARI_DASHBOARD_SRCDIR)

rootfs_install::
	$(Q)set -e; for pair in $(MASAKARI_PATCH_PAIRS); do \
		patchdir=$${pair%%:*}; srcdir=$${pair#*:}; \
		[ -d "$$patchdir" ] || continue; \
		for p in $$(find "$$patchdir" -name '*.py.patch' | sort); do \
			rel=$${p#$$patchdir/}; tgt=$$srcdir/$${rel%.patch}; \
			echo "  PATCH $${tgt#$(ROOTDIR)}"; \
			patch --forward --no-backup-if-mismatch -r - "$$tgt" < "$$p" \
				|| { echo "masakari: failed to apply $$p to $$tgt" >&2; exit 1; }; \
		done; \
	done
