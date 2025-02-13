# CUBE SDK

rootfs_install::
	$(Q)cp -f /usr/local/bin/terraform $(ROOTDIR)/usr/local/bin/
	$(Q)cp -f $(COREDIR)/terraform/scripts/* $(ROOTDIR)/usr/local/bin/
	$(Q)cp -rf $(TOP_BLDDIR)/core/terraform/terraform/ $(ROOTDIR)/var/lib/
