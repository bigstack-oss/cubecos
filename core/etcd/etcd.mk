# Cube SDK
# etcd packages

ETCD_CONF_DIR := /etc/etcd

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(ETCD_CONF_DIR)
	$(Q)cp -f $(TOP_BLDDIR)/core/etcd/etcd* $(ROOTDIR)/usr/local/bin/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(TOP_SRCDIR)/core/etcd/etcd.service ./lib/systemd/system/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(TOP_SRCDIR)/core/etcd/etcd-watch.service ./lib/systemd/system/
