# Cube SDK
# haproxy packages

ROOTFS_DNF += haproxy

rootfs_install::
	$(Q)mkdir -p $(ROOTDIR)/run/haproxy
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/haproxy/haproxy-ha.service ./lib/systemd/system
