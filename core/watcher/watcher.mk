# Cube SDK
# watcher installation

# https://releases.openstack.org/antelope/index.html#antelope-watcher
WATCHER_VER := 10.0.0

WATCHER_CONF_DIR := /etc/watcher
WATCHER_APP_DIR := /var/cache/watcher
WATCHER_LOG_DIR := /var/log/watcher
WATCHER_RUN_DIR := /var/run/watcher

WATCHER_SRCDIR := $(ROOTDIR)/opt/openstack-antelope/lib/python$(PYTHON_VER)/site-packages
WATCHER_PATCHDIR := $(COREDIR)/watcher/$(OPENSTACK_RELEASE)_patch

# watcher-dashboard publishes neither stable/2023.1 nor unmaintained/2023.1 -- both
# branches were deleted at EOL -- so pin the tag instead. 2023.1-eol is 9.0.0 plus
# two commits that touch only .gitreview and tox.ini, exactly the relationship
# yoga-eol has to 7.0.0, and yoga-eol is what installpip's branch fallback chain
# resolves to today.
WATCHER_DASHBOARD_REPO_URL := https://github.com/openstack/watcher-dashboard.git
WATCHER_DASHBOARD_TAG := 2023.1-eol

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/watcher
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/watcher

# install watcher inside the python 3.10 virtual environment
#
# The RDO rpms openstack-watcher-{api,applier,decision-engine,common} and
# python3-watcher are what this replaces. openstack-watcher.spec has no
# watcher-dist.conf, no rootwrap and no sudoers, and it deletes the wheel's whole
# /usr/etc tree -- the only data_files there are the config sample, a README and the
# oslo-config-generator input -- so unlike heat, ironic and manila there is nothing
# to relocate out of the venv prefix. The watcher user and group come from
# core/heavyfs/account/centos9 statically, so shadow-utils is not needed either.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			python-watcher==$(WATCHER_VER)"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries. This is exactly the set the rpms put in /usr/bin, which is
	$(Q)# every console_script watcher declares.
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/watcher-api /usr/bin/watcher-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/watcher-api-wsgi /usr/bin/watcher-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/watcher-applier /usr/bin/watcher-applier
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/watcher-db-manage /usr/bin/watcher-db-manage
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/watcher-decision-engine /usr/bin/watcher-decision-engine
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/watcher-status /usr/bin/watcher-status
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/watcher-sync /usr/bin/watcher-sync

# install the watcher web ui plugin
#
# venv-only since #609: horizon runs in the python 3.10 venv now, so that is where
# the panels registered by core/horizon/horizon.mk resolve watcher_dashboard. The
# dashboard and the client both come from the clone's requirements.txt under the
# antelope constraint, which resolves python-watcherclient to 4.1.0.
#
# python-watcherclient owns the "optimize" osc plugin entry point, which hex_sdk's
# health_watcher_check() drives as `openstack optimize service list`. It used to be
# installed a second time into the system python 3.9 as well, because
# /usr/bin/openstack was `#!/usr/bin/python3` and could only see entry points there;
# core/heavyfs moved the cli into this venv, so that second install is gone and the
# venv copy is the only one.
#
# The 3.9 install also owned /usr/local/bin/watcher, which is where the client's own
# cli came from -- /usr/bin held only the watcher-* service scripts linked above. Since
# /usr/local/bin precedes /usr/bin in the PATH hex_sdk sets, the replacement is a
# /usr/bin/watcher symlink into the venv, the same shape core/monasca uses.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(WATCHER_DASHBOARD_TAG) --depth 1 $(WATCHER_DASHBOARD_REPO_URL) /tmp/watcher/watcher-dashboard
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		-r /tmp/watcher/watcher-dashboard/requirements.txt
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/watcher/watcher-dashboard && \
		/opt/openstack-antelope/bin/python setup.py install"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# the client's own cli, replacing the /usr/local/bin/watcher the 3.9 install
	$(Q)# used to leave behind
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/watcher /usr/bin/watcher

# install system directories and files
#
# watcher.conf.sample is generated and checked in so builds stay reproducible and
# config diffs remain reviewable. It is oslo-config-generator run over
# oslo-config-generator/watcher.conf, which is byte-identical to upstream's copy at
# the 10.0.0 tag, with two adjustments the RDO spec also makes or needs:
#   - #pybasedir is stripped; its default is the build path and is meaningless here.
#   - watcher.objects.register_all() is called before the generator, otherwise
#     stevedore fails to load the "taskflow" opts entry point ("module
#     watcher.objects has no attribute action_plan") and the sample silently loses
#     the [watcher_workflow_engines.taskflow] section.
# The result is 45 sections and 336 options, matching the published 2023.1 reference
# exactly bar oslo.messaging's rabbit_quroum -> rabbit_quorum typo fix.
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

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/watcher
