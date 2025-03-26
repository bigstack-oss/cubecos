# Cube SDK
# watcher installation

WATCHER_CONF_DIR := /etc/watcher
WATCHER_APP_DIR := /var/cache/watcher
WATCHER_LOG_DIR := /var/log/watcher

ROOTFS_DNF_NOARCH += openstack-watcher-api openstack-watcher-applier openstack-watcher-decision-engine

# https://releases.openstack.org/teams/watcher.html
ROOTFS_PIP_DL_FROM_TAG_YOGA += https://github.com/openstack/watcher-dashboard.git

WATCHER_SRCDIR := $(ROOTDIR)/usr/lib/python3.9/site-packages
WATCHER_PATCHDIR := $(COREDIR)/watcher/$(OPENSTACK_RELEASE)_patch

rootfs_install::
	$(Q)cp -f $(PIPS_DIR)/watcher-dashboard.git/watcher_dashboard/local/enabled/_310*.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
	$(Q)cp -f $(PIPS_DIR)/watcher-dashboard.git/watcher_dashboard/conf/watcher_policy.json $(ROOTDIR)/$(HORIZON_DIR)/conf/

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(WATCHER_CONF_DIR) $(WATCHER_APP_DIR) $(WATCHER_LOG_DIR)
	$(Q)chroot $(ROOTDIR) chown watcher:watcher $(WATCHER_CONF_DIR) $(WATCHER_APP_DIR) $(WATCHER_LOG_DIR)
	$(Q)cp -f $(ROOTDIR)/$(WATCHER_CONF_DIR)/watcher.conf $(ROOTDIR)/$(WATCHER_CONF_DIR)/watcher.conf.def

rootfs_install::
	$(Q)[ -d $(WATCHER_PATCHDIR) ] && cp -rf $(WATCHER_PATCHDIR)/* $(WATCHER_SRCDIR)/ || /bin/true
