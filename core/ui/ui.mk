# Cube SDK
# CubeCOS UI installation

# ui log
UI_LOG_DIR := /var/log/cube-cos-ui

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(UI_LOG_DIR)

# ui installation
UI_RPM = $(TOP_BLDDIR)/core/ui/ui.rpm

rootfs_install::
	$(Q)cp -f $(UI_RPM) $(ROOTDIR)/tmp
	$(Q)chroot $(ROOTDIR) dnf install -y /tmp/ui.rpm
	$(Q)rm -rf /tmp/api.rpm
