# Cube SDK
# Intel ixgbe out-of-tree driver installation

# The Intel E610 (0x57AE-0x57B2) is claimed by no in-tree ixgbe older than Linux 6.14, and
# the kernel here is the Kmods SIG 6.12 LTS: its ixgbe loads, binds nothing, and the port
# never shows up. Intel's out-of-tree driver carries E610 and builds against 6.12, so it is
# compiled against $(KERNEL_VERS) and installed under updates/, which the image's
# /etc/depmod.d/dist.conf searches ahead of the in-tree kernel/ copy. The module name stays
# ixgbe, so it takes over every 82598/82599/X540/X550 port as well -- one module, one
# driver, which is how Intel ships it.
IXGBE_VER := 6.4.5
IXGBE_TGZ := ixgbe-$(IXGBE_VER).tar.gz
# $(GITHUB_DL_BASE), not a literal host: this is a GitHub release asset, see project.mk.
IXGBE_DL_URL := $(GITHUB_DL_BASE)/intel/ethernet-linux-ixgbe/releases/download/v$(IXGBE_VER)
# The GitHub release carries no checksum. This is the SHA256 Intel's download center
# publishes for the same tarball (intel.com/content/www/us/en/download/14302), so it moves
# with IXGBE_VER.
IXGBE_SHA256 := 8d23f2c329e0b93055236e67ffbf1de99d8dce32ccc75beb759774c7c24d7ed4
IXGBE_BLDDIR = $(TOP_BLDDIR)/core/ixgbe

# As with thanos, download to .part and only rename once the digest matches.
$(ARCS_DIR)/$(IXGBE_TGZ):
	$(Q)wget $(IXGBE_DL_URL)/$(IXGBE_TGZ) -O $@.part
	$(Q)echo "$(IXGBE_SHA256)  $@.part" | sha256sum -c -
	$(Q)mv $@.part $@

# Compiled in the jail rather than the chroot: the jail carries kernel-devel for exactly
# $(KERNEL_VERS) (jail/jail.ubi9.dockerfile). BUILD_KERNEL keeps Intel's Makefile off
# `uname -r`, which is the build host's kernel. modules_install rather than install, which
# would also run dracut; INSTALL_MOD_STRIP drops ~17 MB of debug info. The modinfo check
# fails the build if depmod resolves ixgbe to anything without the E610 10GBASE-T id.
rootfs_install:: $(ARCS_DIR)/$(IXGBE_TGZ)
	$(Q)rm -rf $(IXGBE_BLDDIR) && mkdir -p $(IXGBE_BLDDIR)
	$(Q)tar -xzf $< -C $(IXGBE_BLDDIR)
	$(Q)$(MAKE) -C $(IXGBE_BLDDIR)/ixgbe-$(IXGBE_VER)/src BUILD_KERNEL=$(KERNEL_VERS) \
		INSTALL_MOD_PATH=$(ROOTDIR) INSTALL_MOD_STRIP=1 modules_install
	$(Q)chroot $(ROOTDIR) depmod -a $(KERNEL_VERS)
	$(Q)chroot $(ROOTDIR) modinfo -k $(KERNEL_VERS) -F alias ixgbe | grep -qi 'v00008086d000057B0'
