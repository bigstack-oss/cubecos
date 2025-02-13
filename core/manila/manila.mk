# Cube SDK
# manila installation

ROOTFS_DNF_NOARCH += openstack-manila openstack-manila-share openstack-manila-ui python3-manilaclient

MANILA_CONFDIR := $(ROOTDIR)/etc/manila
OPENSTACK_DASHBOARD := $(ROOTDIR)/usr/share/openstack-dashboard/openstack_dashboard

MANILA_SRCDIR := $(ROOTDIR)/usr/lib/python3.9/site-packages/manila
MANILA_PATCHDIR := $(COREDIR)/manila/$(OPENSTACK_RELEASE)_patch

rootfs_install::
	$(Q)[ -d $(MANILA_PATCHDIR) ] && cp -rf $(MANILA_PATCHDIR)/* $(MANILA_SRCDIR)/ || /bin/true

rootfs_install::
	# configuration changes
	$(Q)cp -f $(MANILA_CONFDIR)/manila.conf $(MANILA_CONFDIR)/manila.conf.org
	$(Q)cp -f $(COREDIR)/manila/manila.conf.def $(MANILA_CONFDIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/manila/openstack-manila-share.service ./lib/systemd/system
	$(Q)cp -f $(COREDIR)/manila/local/local_settings.d/_90_manila_shares.py $(OPENSTACK_DASHBOARD)/local/local_settings.d/
