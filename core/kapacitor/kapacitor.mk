# Cube SDK
# Kapacitor installation

KAPACITOR_PKG := kapacitor-1.5.7-1.x86_64.rpm

ROOTFS_DNF_DL_FROM += https://dl.influxdata.com/kapacitor/releases/$(KAPACITOR_PKG)

rootfs_install::
	$(Q)chroot $(ROOTDIR) systemctl disable kapacitor
	$(Q)mv -f $(ROOTDIR)/etc/kapacitor/kapacitor.conf $(ROOTDIR)/etc/kapacitor/kapacitor.conf.org
	$(Q)cp -f $(COREDIR)/kapacitor/kapacitor.conf $(ROOTDIR)/etc/kapacitor/kapacitor.conf.def
	$(Q)cp -rf $(COREDIR)/kapacitor/tasks $(ROOTDIR)/etc/kapacitor/
	$(Q)cp -rf $(COREDIR)/kapacitor/templates $(ROOTDIR)/etc/kapacitor/
	$(Q)cp -rf $(COREDIR)/kapacitor/handlers $(ROOTDIR)/etc/kapacitor/
	$(Q)mkdir -p $(ROOTDIR)/etc/kapacitor/config_handlers $(ROOTDIR)/var/alert_resp $(ROOTDIR)/var/response
