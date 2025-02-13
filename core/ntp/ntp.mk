# Cube SDK
# ntp installation

ROOTFS_DNF += chrony

rootfs_install::
	$(Q)chroot $(ROOTDIR) systemctl disable chronyd
