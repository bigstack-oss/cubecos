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
	$(Q)cp -f $(CINDER_CONFDIR)/cinder.conf $(CINDER_CONFDIR)/cinder.conf.org
	$(Q)touch $(CINDER_CONFDIR)/cinder.conf.def
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cinder/cinder.d
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cinder/external_storage_extra_configs
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/openstack-cinder-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/openstack-cinder-scheduler.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/openstack-cinder-volume.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/openstack-cinder-backup.service ./lib/systemd/system
#	$(Q)cp -f $(COREDIR)/cinder/db_schema_stein.tgz $(CINDER_CONFDIR)
	$(Q)chroot $(ROOTDIR) systemctl disable multipathd iscsi
	$(Q)chroot $(ROOTDIR) mkdir -p /usr/share/cube/cos/cinder
	$(Q)chroot $(ROOTDIR) mkdir -p /usr/share/cube/cos/cinder/builtin_models
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/builtin_models/dell_emc-sc-storagecenter_fc-SCFCDriver.yaml ./usr/share/cube/cos/cinder/builtin_models
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/cinder
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/cinder/models
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/cinder/storage_extra_configs_ownership
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/multipath/conf.d
