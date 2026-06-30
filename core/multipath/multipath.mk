# CUBE SDK -- multipath storage fabric.
# Consolidates the multipath bits formerly split across ceph.mk + cinder.mk:
# the base /etc/multipath.conf (with the global overrides{}), the per-backend
# /etc/multipath/conf.d, the device-mapper-multipath package, and disabling the
# service at build (config_multipath enables + reconfigures it at commit).

ROOTFS_DNF += device-mapper-multipath

rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/multipath/multipath.conf ./etc/
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/multipath/conf.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/builtin_models/multipath/dell_emc-sc-storagecenter_fc-SCFCDriver.conf ./etc/multipath/conf.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/builtin_models/multipath/dell_emc-powerstore-driver-PowerStoreDriver.conf ./etc/multipath/conf.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/builtin_models/multipath/nfs-NfsDriver.conf ./etc/multipath/conf.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/builtin_models/multipath/fujitsu-eternus_dx-eternus_dx_fc-FJDXFCDriver.conf ./etc/multipath/conf.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/builtin_models/multipath/fujitsu-eternus_dx-eternus_dx_iscsi-FJDXISCSIDriver.conf ./etc/multipath/conf.d
	$(Q)chroot $(ROOTDIR) systemctl disable multipathd
