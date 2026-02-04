# Cube SDK
# glance installation

ROOTFS_DNF_NOARCH += openstack-glance

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p /var/lib/glance/mnt
	$(Q)chroot $(ROOTDIR) mkdir -p /var/lib/glance/locks
	$(Q)chroot $(ROOTDIR) mkdir -p /var/lib/glance/image-cache
	$(Q)chroot $(ROOTDIR) chown -R glance:glance /var/lib/glance
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/glance/cirros-0.4.0-x86_64-disk.qcow2 ./etc/glance
	$(Q)cp -f $(ROOTDIR)/etc/glance/glance-api.conf $(ROOTDIR)/etc/glance/glance-api.conf.org
	$(Q)touch $(ROOTDIR)/etc/glance/glance-api.conf.def
	$(Q)cp -f $(COREDIR)/glance/policy.yaml $(ROOTDIR)/etc/glance/
	$(Q)chroot $(ROOTDIR) chown glance:glance /etc/glance/policy.yaml
