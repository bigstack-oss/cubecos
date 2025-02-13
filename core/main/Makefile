# CUBE SDK

include ../../build.mk

##################################################################################
#
#  Configure release numbers and policy info here
#
##################################################################################

# Product Release Version Numbers
RELEASE_VERSION := 3.0.0
PRE_RELEASE_VERSION := 2.5.0

##################################################################################
#
#        ATTENTION:  Likely you should not be altering this file beyond this point.
#
##################################################################################

PROJ_NAME         := CUBE
PROJ_LONGNAME     := Cube Appliance

PROJ_VENDOR_NAME     := CUBE
PROJ_VENDOR_LONGNAME := Cube Appliance

ifeq ($(CUSTOM_beta),1)
PROJ_VERSION := $(PRE_RELEASE_VERSION)
PROJ_VENDOR_VERSION := $(PRE_RELEASE_VERSION)
else
PROJ_VERSION := $(RELEASE_VERSION)
PROJ_VENDOR_VERSION := $(RELEASE_VERSION)
endif

PROJ_README_TEMPLATE := $(SRCDIR)/README.txt.in
PROJ_BUILD_PPU := 1
PROJ_BUILD_TEST_HOTFIXES := 1
PROJ_BUILD_PXE := 1
PROJ_BUILD_PXESERVER := 1
PROJ_BUILD_PXESERVER_ISO := 1
PROJ_BUILD_PXEDEPLOY := 1
PROJ_BUILD_USB := 1
PROJ_BUILD_LIVE_USB := 1
PROJ_BUILD_ISO := 1
PROJ_BUILD_OVA := 1
PROJ_BUILD_VAGRANT := 1
ifeq ($(PRODUCTION),1)
PROJ_BUILD_EXT := 1
endif

PROJ_HARDWARE_DIR := $(SRCDIR)/../hardware
PROJ_HARDWARE += vmware
PROJ_HARDWARE += dell_poweredge_xr

PROJ_NFS_SERVER := 10.32.0.200
PROJ_NFS_PATH := /volume1/pxe-server

# Generic Cube
# NOTE: THIS MUST BE THE LAST!
PROJ_HARDWARE += generic

PROJ_BASE_ROOTFS = $(CURDIR)/rootfs

# cube system files
include $(SRCDIR)/cube.mk

ROOT_COMPONENTS += cubectl
include $(shell for m in $(ROOT_COMPONENTS); do ls $(COREDIR)/$$m/$$m.mk; done)

# cube finalizer
include $(SRCDIR)/cube-post.mk

$(PROJ_BASE_ROOTFS): $(TOP_BLDDIR)/core/heavyfs/heavy_rootfs $(PROJ_BOOTSTRAP) $(PROGRAMS) $(shell for m in $(ROOT_COMPONENTS); do find $(COREDIR)/$$m -type f; done)
	$(call RUN_CMD_TIMED,rm -rf $@,"  RM      $$(basename $@)")
	$(call RUN_CMD_TIMED,cp -rpf $< $@,"  COPY    $$(basename $<)")

PKGCLEAN += $(CURDIR)/*.before rootfs *initramfs

liveusb: liveusb_warning

.PHONY:
liveusb_warning:
	@echo '***'
	@echo '***'
	@echo '*** Warning: The liveusb image can only be used for QEMU testing.'
	@echo '***          The liveusb image should never be used on real hardware.'
	@echo '***'
	@echo '***'

pxeserver_ramdisk_install::
	$(Q)sed -i "s/Hex Appliance/$(PROJ_LONGNAME)/" $(ROOTDIR)/etc/settings.sys
	$(Q)sed -i "s/Hex/$(PROJ_NAME)/" $(ROOTDIR)/etc/settings.sys
	$(Q)sed -i "s/1.0/$(RELEASE_VERSION)/" $(ROOTDIR)/etc/settings.sys
	$(Q)sed -i "s/hex/cube/" $(ROOTDIR)/etc/settings.sys
	$(Q)sed -i 1,6d $(ROOTDIR)/etc/settings.sys
	$(Q)echo "Welcome to $(PROJ_LONGNAME) pxe installer" > $(ROOTDIR)/etc/motd

pxeserver_iso_ramdisk_install::
	$(Q)sed -i "s/Hex Appliance/$(PROJ_LONGNAME)/" $(ROOTDIR)/etc/settings.sys
	$(Q)sed -i "s/Hex/$(PROJ_NAME)/" $(ROOTDIR)/etc/settings.sys
	$(Q)sed -i "s/1.0/$(RELEASE_VERSION)/" $(ROOTDIR)/etc/settings.sys
	$(Q)sed -i "s/hex/cube/" $(ROOTDIR)/etc/settings.sys
	$(Q)sed -i 1,6d $(ROOTDIR)/etc/settings.sys
	$(Q)echo "Welcome to $(PROJ_LONGNAME) pxe installer" > $(ROOTDIR)/etc/motd

include $(HEX_MAKEDIR)/hex_sdk.mk

PROJ_BOOTSTRAP += $(COREDIR)/main/bootstrap_cube_config
