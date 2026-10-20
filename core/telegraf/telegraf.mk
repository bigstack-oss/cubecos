# Cube SDK
# Telegraf installation

TELEGRAF_VER := 1.40.2
TELEGRAF_PKG := telegraf-$(TELEGRAF_VER)-1.x86_64.rpm

# The copy in InfluxData's repository, which is signed with its key (core/influxdb); the one on
# dl.influxdata.com is the same build, unsigned
ROOTFS_DNF_DL_FROM += https://repos.influxdata.com/rhel/9/x86_64/stable/$(TELEGRAF_PKG)

# /usr/bin/telegraf is rebuilt here from the same tag and installed over the rpm's. Upstream builds
# each release with the Go of its day and never rebuilds it. Through 1.30.3 core/telegraf/Makefile
# rebuilt it for that reason: the 1.30.3 rpm was go1.22.3 and carried 127 advisories, the rebuild
# 66 (cubecos#647). 1.40.1 shipped the rpm's binary, built with the toolchain of its day, go1.27.1
# (cubecos#801). 1.40.2 is still go1.27.1, older than the October 2026 security release
# (1.27.2 / 1.26.9), and links an x/net older than its fix; the jail's Go and TELEGRAF_GO_GET cover
# both. The rpm stays for the unit, the config and the version the SBOM names, and `rpm -V telegraf`
# reports the binary as modified. The build flags and version ldflags are upstream's release ones.
#
# Return to the rpm's binary on the condition core/exporters/Makefile gives. Judge a bump, or
# answer an audit, by the binary rather than by the version number: `go version -m` and
# `govulncheck -mode binary` on the rpm payload's ./usr/bin/telegraf (`rpm2cpio <rpm> | cpio -idm`).
TELEGRAF_GO_GET := golang.org/x/crypto@v0.58.0 golang.org/x/net@v0.61.0 golang.org/x/text@v0.43.0
TELEGRAF_GO_DIR := $(ARCS_DIR)/telegraf-go
TELEGRAF_SRC := $(TELEGRAF_GO_DIR)/telegraf-$(TELEGRAF_VER)-src
TELEGRAF_BIN := $(TELEGRAF_GO_DIR)/bin/telegraf
TELEGRAF_VERSION_PKG := github.com/influxdata/telegraf/internal

# The tag is cloned shallow, and the modules come from proxy.golang.org, checked against
# sum.golang.org.
$(TELEGRAF_SRC):
	$(call RUN_CMD_TIMED, rm -rf $@.part && \
		git clone -q --depth 1 -b v$(TELEGRAF_VER) https://github.com/influxdata/telegraf.git $@.part && \
		mv $@.part $@,"  CLONE   telegraf-$(TELEGRAF_VER)")

$(TELEGRAF_BIN): $(TELEGRAF_SRC) $(COREDIR)/telegraf/telegraf.mk
	$(Q)mkdir -p $(@D)
	$(call RUN_CMD_TIMED, cd $< && go get $(TELEGRAF_GO_GET) && go mod tidy && \
		CGO_ENABLED=0 go build -trimpath \
		-ldflags "-w -s -X $(TELEGRAF_VERSION_PKG).Version=$(TELEGRAF_VER) \
			-X $(TELEGRAF_VERSION_PKG).Commit=$$(git rev-parse --short HEAD) -X $(TELEGRAF_VERSION_PKG).Branch=HEAD" \
		-o $@ ./cmd/telegraf,"  BUILD   telegraf-$(TELEGRAF_VER)")

rootfs_install:: $(TELEGRAF_BIN)
	$(Q)install -m 0755 $(TELEGRAF_BIN) $(ROOTDIR)/usr/bin/telegraf

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
