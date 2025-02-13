# Cube SDK
# glance installation

ROOTFS_DNF_NOARCH += openstack-glance

rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/glance/cirros-0.4.0-x86_64-disk.qcow2 ./etc/glance
	$(Q)cp -f $(ROOTDIR)/etc/glance/glance-api.conf $(ROOTDIR)/etc/glance/glance-api.conf.def
