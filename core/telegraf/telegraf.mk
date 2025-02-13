# Cube SDK
# Telegraf installation

TELEGRAF_PKG := telegraf-1.17.2-1.x86_64.rpm

ROOTFS_DNF_DL_FROM += https://dl.influxdata.com/telegraf/releases/$(TELEGRAF_PKG)

BIN := $(TOP_BLDDIR)/core/telegraf/telegraf/telegraf

rootfs_install::
	$(Q)chroot $(ROOTDIR) systemctl disable telegraf
	$(Q)mv -f $(ROOTDIR)/etc/telegraf/telegraf.conf $(ROOTDIR)/etc/telegraf/telegraf.conf.org
	$(Q)cp -f $(BIN) $(ROOTDIR)/usr/bin/
	$(Q)cp -f $(COREDIR)/telegraf/telegraf.conf.in $(ROOTDIR)/etc/telegraf/telegraf.conf.in
	$(Q)cp -f $(COREDIR)/telegraf/telegraf-ctrl.conf.in $(ROOTDIR)/etc/telegraf/telegraf-ctrl.conf.in
	$(Q)cp -f $(COREDIR)/telegraf/telegraf-device-linux.conf.in $(ROOTDIR)/etc/telegraf/telegraf-device-linux.conf.in
	$(Q)cp -f $(COREDIR)/telegraf/telegraf-device-win.conf.in $(ROOTDIR)/etc/telegraf/telegraf-device-win.conf.in
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/telegraf/telegraf_sudoers ./etc/sudoers.d/
