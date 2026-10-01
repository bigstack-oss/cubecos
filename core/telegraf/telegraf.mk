# Cube SDK
# Telegraf installation

TELEGRAF_PKG := telegraf-1.40.1-1.x86_64.rpm

ROOTFS_DNF_DL_FROM += https://dl.influxdata.com/telegraf/releases/$(TELEGRAF_PKG)

# The rpm's own /usr/bin/telegraf is what ships. Through 1.30.3 core/telegraf/Makefile
# rebuilt the tag and copied that binary over it, because upstream builds each release with
# the Go of its day and never rebuilds it: the 1.30.3 rpm was go1.22.3 and carried 127
# advisories, the rebuild 66 (cubecos#647). 1.40.1 is built with go1.27.1, the current
# toolchain, and govulncheck reports the identical two advisories for the rpm's binary and
# for a go1.27.1 rebuild of the same tag (cubecos#801), so the rebuild buys nothing -- and it
# would need a toolchain the jail does not have: the tag requires go 1.27, the jail is on
# 1.25. The packaged binary also keeps `rpm -V telegraf` clean and the SBOM honest, and it
# is stripped: 328 MB, against 456 MB for our build.
#
# The trade is that the toolchain now moves only when telegraf does. Upstream releases every
# few weeks with the Go of the day, so a current telegraf is a current toolchain and an old
# one ages. Judge a bump, or answer an audit, by scanning the rpm payload rather than by the
# version number: `rpm2cpio <rpm> | cpio -idm && govulncheck -mode binary ./usr/bin/telegraf`.

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
#
# One line of that payload has to go, though. 1.30 added `ImportCredential=telegraf.*`,
# a directive systemd only learned in v254; CentOS Stream 9 is on 252, so it logs
# "Unknown key name 'ImportCredential' in section 'Service', ignoring" -- twice per
# `systemctl daemon-reload`, which every hex_config commit triggers. A drop-in cannot
# unset a key the base unit's parser rejected, so it is stripped here instead. Nothing
# feeds telegraf systemd credentials, so the directive is inert either way.
rootfs_install::
	$(Q)cp -f $(ROOTDIR)/usr/lib/telegraf/scripts/telegraf.service $(ROOTDIR)/usr/lib/systemd/system/telegraf.service
	$(Q)sed -i '/^ImportCredential=/d' $(ROOTDIR)/usr/lib/systemd/system/telegraf.service
	$(Q)chroot $(ROOTDIR) systemctl disable telegraf
	$(Q)mv -f $(ROOTDIR)/etc/telegraf/telegraf.conf $(ROOTDIR)/etc/telegraf/telegraf.conf.org
	$(Q)cp -f $(COREDIR)/telegraf/telegraf.conf.in $(ROOTDIR)/etc/telegraf/telegraf.conf.in
	$(Q)cp -f $(COREDIR)/telegraf/telegraf-ctrl.conf.in $(ROOTDIR)/etc/telegraf/telegraf-ctrl.conf.in
	$(Q)cp -f $(COREDIR)/telegraf/telegraf-device-linux.conf.in $(ROOTDIR)/etc/telegraf/telegraf-device-linux.conf.in
	$(Q)cp -f $(COREDIR)/telegraf/telegraf-device-win.conf.in $(ROOTDIR)/etc/telegraf/telegraf-device-win.conf.in
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/telegraf/telegraf_sudoers ./etc/sudoers.d/
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/telegraf.service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/telegraf/telegraf-restart.conf ./etc/systemd/system/telegraf.service.d/
