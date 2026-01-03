# Cube SDK
# yq installation

rootfs_install::
	$(Q)cp -f $(TOP_BLDDIR)/core/yq/yq $(ROOTDIR)/usr/local/bin/
	$(Q)chroot $(ROOTDIR) chmod +x /usr/local/bin/yq
