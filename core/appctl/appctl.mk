# Cube SDK
# CubeCOS App Control installation

# appctl directories
APPCTL_CONF_DIR := /etc/cube/appctl

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(APPCTL_CONF_DIR)

# for RC builds
heavyfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(APPCTL_CONF_DIR)

# appctl installation
APPCTL_RPM = $(TOP_BLDDIR)/core/appctl/appctl.rpm
APPCTL_PLUGINS_RPM = $(TOP_BLDDIR)/core/appctl/plugins

rootfs_install::
	$(Q)cp -f $(APPCTL_RPM) $(ROOTDIR)/tmp/
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) dnf install -y /tmp/appctl.rpm
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)rm -rf /tmp/appctl.rpm
	$(Q)mkdir -p $(ROOTDIR)/opt/appfw
	$(Q)cp -r $(APPCTL_PLUGINS_RPM) $(ROOTDIR)/opt/appfw/

# for RC builds
heavyfs_install::
	$(Q)cp -f $(APPCTL_RPM) $(ROOTDIR)/tmp/
	$(Q)chroot $(ROOTDIR) rpm -e cube-cos-appctl
	$(Q)chroot $(ROOTDIR) rpm -i /tmp/appctl.rpm
	$(Q)rm -rf /tmp/appctl.rpm
	$(Q)mkdir -p $(ROOTDIR)/opt/appfw
	$(Q)cp -r $(APPCTL_PLUGINS_RPM) $(ROOTDIR)/opt/appfw/
