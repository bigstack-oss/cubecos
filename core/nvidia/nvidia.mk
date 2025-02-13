# Cube SDK
# nvidia driver installation

ROOTFS_DNF += make kernel-devel elfutils-libelf-devel

NVIDIA_DRIVER := NVIDIA-Linux-x86_64-535.129.03-vgpu-kvm.run

rootfs_install::
	$(Q)cp -f $(COREDIR)/nvidia/$(NVIDIA_DRIVER) $(ROOTDIR)/root
	$(Q)mount -t proc proc $(ROOTDIR)/proc || true
	$(Q)mount -t sysfs sys $(ROOTDIR)/sys || true
	$(Q)mount -o bind /dev $(ROOTDIR)/dev || true
	$(Q)chroot $(ROOTDIR) sh /root/$(NVIDIA_DRIVER) --kernel-name=$(KERNEL_VERS) -s || true
	$(Q)umount -l $(ROOTDIR)/proc || true
	$(Q)umount -l $(ROOTDIR)/sys || true
	$(Q)umount -l $(ROOTDIR)/dev || true
	$(Q)chroot $(ROOTDIR) ls $(KERNEL_MODULE_DIR)/kernel/drivers/video/{nvidia,nvidia-vgpu-vfio}.ko
	$(Q)rm -f $(ROOTDIR)/root/$(NVIDIA_DRIVER)
	$(Q)rm -f $(ROOTDIR)/var/log/nvidia*.log
	$(Q)chroot $(ROOTDIR) systemctl disable nvidia-vgpu-mgr
	$(Q)chroot $(ROOTDIR) systemctl disable nvidia-vgpud

# disable nouveau driver: nouveau is a free and open-source graphics device driver for Nvidia video cards
rootfs_install::
	$(Q)echo "blacklist nouveau" > $(ROOTDIR)/etc/modprobe.d/nvidia-installer-disable-nouveau.conf
	$(Q)echo "options nouveau modeset=0" >> $(ROOTDIR)/etc/modprobe.d/nvidia-installer-disable-nouveau.conf
