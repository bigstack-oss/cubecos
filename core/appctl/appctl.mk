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

rootfs_install::
	$(Q)cp -f $(APPCTL_RPM) $(ROOTDIR)/tmp/
	$(Q)chroot $(ROOTDIR) dnf install -y /tmp/appctl.rpm
	$(Q)rm -rf /tmp/appctl.rpm
	$(Q)cp -f $(COREDIR)/appctl/cube-cos-app-framework.yaml.in $(ROOTDIR)/etc/cube/appctl/
	$(Q)mkdir -p $(ROOTDIR)/opt/appfw
	$(Q)cp -r $(COREDIR)/cube-cos-app-framework/{plugins} $(ROOTDIR)/opt/appfw/

# for RC builds
heavyfs_install::
	$(Q)cp -f $(APPCTL_RPM) $(ROOTDIR)/tmp/
	$(Q)chroot $(ROOTDIR) rpm -e cube-cos-appctl
	$(Q)chroot $(ROOTDIR) rpm -i /tmp/appctl.rpm
	$(Q)rm -rf /tmp/appctl.rpm
	$(Q)cp -f $(COREDIR)/appctl/cube-cos-app-framework.yaml.in $(ROOTDIR)/etc/cube/appctl/
