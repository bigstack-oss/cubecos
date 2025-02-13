# Cube SDK
# cinder installation

ROOTFS_DNF += iscsi-initiator-utils device-mapper-multipath sshpass
ROOTFS_DNF_NOARCH += openstack-cinder targetcli python3-keystone
# support other storage backends
ROOTFS_PIP += purestorage

CINDER_SRCDIR := $(ROOTDIR)/usr/lib/python3.9/site-packages/cinder
CINDER_PATCHDIR := $(COREDIR)/cinder/$(OPENSTACK_RELEASE)_patch

CINDER_CONFDIR := $(ROOTDIR)/etc/cinder

rootfs_install::
	$(Q)[ -d $(CINDER_PATCHDIR) ] && cp -rf $(CINDER_PATCHDIR)/* $(CINDER_SRCDIR)/ || /bin/true

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cinder/cinder.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/openstack-cinder-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/openstack-cinder-scheduler.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/openstack-cinder-volume.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/openstack-cinder-backup.service ./lib/systemd/system
#	$(Q)cp -f $(COREDIR)/cinder/db_schema_stein.tgz $(CINDER_CONFDIR)
	$(Q)cp -f $(CINDER_CONFDIR)/cinder.conf $(CINDER_CONFDIR)/cinder.conf.def
	# $(Q)chroot $(ROOTDIR) systemctl disable qemu-guest-agent multipathd iscsi-onboot iscsi
