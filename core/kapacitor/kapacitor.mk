# Cube SDK
# Kapacitor installation

# Installed from the InfluxData repo core/influxdb/influxdb.repo already configures,
# not from an explicit dl.influxdata.com URL as it was through 1.5.7. The reason is
# verification: the rpms published under dl.influxdata.com/kapacitor/releases/ carry
# `Signature : (none)`, so that path installed an unsigned 87 MB binary, while the same
# build in the repo is signed (RSA/SHA512, key id da61c26a0585bd3b) and dnf checks it.
#
# Pinned in both directions. ROOTFS_DNF names the exact NVR so the build installs 1.8.6-1
# rather than whatever the channel has moved to, and LOCKED_DNF stops installdnf's
# duplicate pass from resolving it to something else -- the same pairing qemu and openssl
# use in core/heavyfs/Makefile. No epoch: LOCKED_DNF is matched as a string against rpm
# filenames and a filename never carries one (see the qemu note there).
KAPACITOR_VER := 1.8.6-1

ROOTFS_DNF += kapacitor-$(KAPACITOR_VER)
LOCKED_DNF += kapacitor-$(KAPACITOR_VER)

rootfs_install::
	$(Q)chroot $(ROOTDIR) systemctl disable kapacitor
	$(Q)mv -f $(ROOTDIR)/etc/kapacitor/kapacitor.conf $(ROOTDIR)/etc/kapacitor/kapacitor.conf.org
	$(Q)cp -f $(COREDIR)/kapacitor/kapacitor.conf $(ROOTDIR)/etc/kapacitor/kapacitor.conf.def
	$(Q)cp -rf $(COREDIR)/kapacitor/tasks $(ROOTDIR)/etc/kapacitor/
	$(Q)cp -rf $(COREDIR)/kapacitor/templates $(ROOTDIR)/etc/kapacitor/
	$(Q)cp -rf $(COREDIR)/kapacitor/handlers $(ROOTDIR)/etc/kapacitor/
	$(Q)cp -rf $(COREDIR)/kapacitor/exec_job_templates $(ROOTDIR)/etc/kapacitor/
	$(Q)mkdir -p $(ROOTDIR)/etc/kapacitor/config_handlers $(ROOTDIR)/var/alert_resp $(ROOTDIR)/var/response
	$(Q)mkdir -p $(ROOTDIR)/usr/share/cube/cos/kapacitor
	$(Q)cp -f $(COREDIR)/kapacitor/event.yaml $(ROOTDIR)/usr/share/cube/cos/kapacitor/
