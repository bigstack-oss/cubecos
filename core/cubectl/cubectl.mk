# Cube SDK

PROG := cubectl

$(call PROJ_INSTALL_PROGRAM,-S,$(TOP_BLDDIR)/core/cubectl/$(PROG),./usr/local/bin)

rootfs_install::
	$(Q)chroot $(ROOTDIR) ln -sf /usr/local/bin/$(PROG) /usr/sbin/
	# scripts
	$(Q)cp -f $(COREDIR)/cubectl/scripts/* $(ROOTDIR)/usr/local/bin/
