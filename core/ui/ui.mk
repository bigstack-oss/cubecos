# Cube SDK
# CubeCOS UI installation

UI_LOG_DIR := /var/log/cube-cos-ui

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(UI_LOG_DIR)
