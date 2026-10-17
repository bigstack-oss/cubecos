# Cube SDK
# nvidia driver installation

ROOTFS_DNF += make kernel-devel elfutils-libelf-devel

NVIDIA_DRIVER := NVIDIA-Linux-x86_64-580.105.06-vgpu-kvm-aie.run
NVIDIA_DRIVER_DIR := /root/$(NVIDIA_DRIVER:.run=)
NVIDIA_PATCHDIR := $(COREDIR)/nvidia/patch

# Blackwell GPUs (e.g. RTX PRO 6000 Blackwell Server Edition, 10de:2bb5) run on the open kernel
# module only: on a vGPU host the proprietary nvidia.ko refuses them ("not supported by
# proprietary nvidia.ko") and initializes none. So the open module is installed, and the license
# check below fails the build if the proprietary one is installed instead. The cost is the RTX
# A2000: this package's open module cannot initialize it (RmInitAdapter fails to prepare its GSP
# scrubber ucode), so it is unsupported until both module types can be shipped.
#
# patch/: the kernel-open changes this driver needs to build and run on the Linux 7.2 kernel, each a
# kernel-open/<path>.patch; patch/README.md says what they carry and under which license. Every one is
# behind a conftest probe, so the patched sources build for 6.12 as well. The installer is extracted
# afresh each build, so a patch always meets the pristine file; a driver that already carries a
# change makes its patch fail, which is the cue to drop it.
rootfs_install::
	$(Q)rm -rf $(ROOTDIR)$(NVIDIA_DRIVER_DIR)
	$(Q)sh $(COREDIR)/nvidia/$(NVIDIA_DRIVER) -x --target $(ROOTDIR)$(NVIDIA_DRIVER_DIR)
	$(Q)set -e; for p in $$(cd $(NVIDIA_PATCHDIR) && find kernel-open -name '*.patch' | sort); do \
		tgt=$(ROOTDIR)$(NVIDIA_DRIVER_DIR)/$${p%.patch}; \
		patch --forward --no-backup-if-mismatch -r - "$$tgt" < $(NVIDIA_PATCHDIR)/$$p \
			|| { echo "nvidia: failed to apply $$p to $$tgt" >&2; exit 1; }; \
	done
	$(Q)mount -t sysfs sys $(ROOTDIR)/sys || true
	$(Q)mount -o bind /dev $(ROOTDIR)/dev || true
	$(Q)chroot $(ROOTDIR) sh -c "cd $(NVIDIA_DRIVER_DIR) && ./nvidia-installer \
		--kernel-name=$(KERNEL_VERS) \
		--kernel-module-type=open \
		-s" || true
	$(Q)umount -l $(ROOTDIR)/sys || true
	$(Q)umount -l $(ROOTDIR)/dev || true
	$(Q)chroot $(ROOTDIR) ls $(KERNEL_MODULE_DIR)/kernel/drivers/video/{nvidia,nvidia-vgpu-vfio}.ko
	$(Q)chroot $(ROOTDIR) modinfo -F license $(KERNEL_MODULE_DIR)/kernel/drivers/video/nvidia.ko | grep -qx "Dual MIT/GPL"
	$(Q)rm -rf $(ROOTDIR)$(NVIDIA_DRIVER_DIR)
	$(Q)rm -f $(ROOTDIR)/var/log/nvidia*.log
	$(Q)chroot $(ROOTDIR) systemctl disable nvidia-vgpu-mgr
	$(Q)chroot $(ROOTDIR) systemctl disable nvidia-vgpud

# disable nouveau driver: nouveau is a free and open-source graphics device driver for Nvidia video cards
rootfs_install::
	$(Q)echo "blacklist nouveau" > $(ROOTDIR)/etc/modprobe.d/nvidia-installer-disable-nouveau.conf
	$(Q)echo "options nouveau modeset=0" >> $(ROOTDIR)/etc/modprobe.d/nvidia-installer-disable-nouveau.conf

NVIDIA_FABRIC_MANAGER_RPM := nvidia-fabricmanager-580.105.06-1.x86_64.rpm

rootfs_install::
	$(Q)cp -f $(COREDIR)/nvidia/$(NVIDIA_FABRIC_MANAGER_RPM) $(ROOTDIR)/tmp/
	$(Q)chroot $(ROOTDIR) dnf install -y /tmp/$(NVIDIA_FABRIC_MANAGER_RPM)
	$(Q)rm -rf /tmp/$(NVIDIA_FABRIC_MANAGER_RPM)
