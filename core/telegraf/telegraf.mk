# Cube SDK
# Telegraf installation

TELEGRAF_PKG := telegraf-1.30.3-1.x86_64.rpm

ROOTFS_DNF_DL_FROM += https://dl.influxdata.com/telegraf/releases/$(TELEGRAF_PKG)

BIN := $(TOP_BLDDIR)/core/telegraf/telegraf/telegraf

# The rpm carries its unit as a payload file, /usr/lib/telegraf/scripts/telegraf.service,
# and only copies it to /usr/lib/systemd/system from the postinstall scriptlet -- which is
# why `rpm -qf` on a 3.1.0 node reports the installed unit as owned by no package.
#
# 1.17.2 gated that copy on `readlink /proc/1/exe == */systemd`. That is *true* here: the
# build jail runs systemd as pid 1 and mountrootfs bind-mounts /proc into the chroot, so
# the scriptlet saw the jail's init and installed the unit as a side effect. 1.24 changed
# the probe to `[ -d /run/systemd/system ]`, the documented sd_booted() check, and the
# chroot has its own empty /run -- so the unit is never placed and the disable below fails
# with "Failed to disable unit, unit telegraf.service does not exist."
#
# Copy it ourselves from the rpm's own payload, so it stays whatever the packaged version
# ships and no longer depends on a scriptlet probing the build environment.
rootfs_install::
	$(Q)cp -f $(ROOTDIR)/usr/lib/telegraf/scripts/telegraf.service $(ROOTDIR)/usr/lib/systemd/system/telegraf.service
	$(Q)chroot $(ROOTDIR) systemctl disable telegraf
	$(Q)mv -f $(ROOTDIR)/etc/telegraf/telegraf.conf $(ROOTDIR)/etc/telegraf/telegraf.conf.org
	$(Q)cp -f $(BIN) $(ROOTDIR)/usr/bin/
	$(Q)cp -f $(COREDIR)/telegraf/telegraf.conf.in $(ROOTDIR)/etc/telegraf/telegraf.conf.in
	$(Q)cp -f $(COREDIR)/telegraf/telegraf-ctrl.conf.in $(ROOTDIR)/etc/telegraf/telegraf-ctrl.conf.in
	$(Q)cp -f $(COREDIR)/telegraf/telegraf-device-linux.conf.in $(ROOTDIR)/etc/telegraf/telegraf-device-linux.conf.in
	$(Q)cp -f $(COREDIR)/telegraf/telegraf-device-win.conf.in $(ROOTDIR)/etc/telegraf/telegraf-device-win.conf.in
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/telegraf/telegraf_sudoers ./etc/sudoers.d/
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/telegraf.service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/telegraf/telegraf-restart.conf ./etc/systemd/system/telegraf.service.d/
