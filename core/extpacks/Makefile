# CUBE SDK

include ../../build.mk

help::
	@echo "ext          Create project extention pack image (non-recursive)"

MAIN_DIR := $(TOP_BLDDIR)/core/main
SHIP_DIR := $(MAIN_DIR)/ship
FULL += ext

PROJ_EXT := $(MAIN_DIR)/proj.ext
PKGCLEAN += $(PROJ_EXT)
NAS := $(TOP_BLDDIR)/nas
PROJ_NFS_SERVER := 10.32.0.200
PROJ_NFS_OPENSTACK_PATH := /volume1/openstack-images

AMPHORA := $(TOP_BLDDIR)/../amphora-x64-haproxy-yoga.qcow2
MANILA  := $(TOP_BLDDIR)/../manila-service-image-yoga.qcow2
RANCHER := $(TOP_BLDDIR)/../rancher-cluster-image.raw
EXTPACK := $(AMPHORA) $(MANILA) $(RANCHER)
EXTPACK_MD5 := $(shell for E in $(EXTPACK); do echo $${E}.md5 ; done)

PROJ_PORTAL_EXT := $(MAIN_DIR)/proj.portal.ext
PKGCLEAN += $(PROJ_PORTAL_EXT)
PORTALPACK ?= $(NAS)/standard/ubuntu2404.qcow2 \
$(NAS)/standard/CentOS-Stream-9.qcow2 \
$(NAS)/standard/fedora40.qcow2 \
$(NAS)/standard/debian-12-bookworm.qcow2 \
$(NAS)/standard/rocky9.qcow2

$(NAS):
	$(Q)[ -d $@ ] || mkdir -p $@
	$(Q)mount -o ro $(PROJ_NFS_SERVER):$(PROJ_NFS_OPENSTACK_PATH)/ $@

$(AMPHORA): $(NAS)
	$(Q)cp $</yoga/amphora-x64-haproxy-yoga.qcow2 $@

.PHONY: $(AMPHORA).md5
$(AMPHORA).md5: $(AMPHORA)
	$(Q)diff $@ $(NAS)/yoga/amphora-x64-haproxy-yoga.qcow2.md5 2>/dev/null || ( cp -f $(NAS)/yoga/amphora-x64-haproxy-yoga.qcow2 $< && md5sum $< | awk '{print $$1}' > $@ )

$(MANILA): $(NAS)
	$(Q)cp $</yoga/manila-service-image-yoga.qcow2 $@

.PHONY: $(MANILA).md5
$(MANILA).md5: $(MANILA)
	$(Q)diff $@ $(NAS)/yoga/manila-service-image-yoga.qcow2.md5 2>/dev/null || ( cp -f $(NAS)/yoga/manila-service-image-yoga.qcow2 $< && md5sum $< | awk '{print $$1}' > $@ )

$(RANCHER): $(NAS)
	$(Q)cp $</yoga/rancher-cluster-image.raw $@

.PHONY: $(RANCHER).md5
$(RANCHER).md5: $(RANCHER)
	$(Q)diff $@ $(NAS)/yoga/rancher-cluster-image.raw.md5 2>/dev/null || ( cp -f $(NAS)/yoga/rancher-cluster-image.raw $< && md5sum $< | awk '{print $$1}' > $@ )

.PHONY: ext
ext: $(PROJ_EXT) $(PROJ_PORTAL_EXT)
	@true

# Create extention package
$(PROJ_EXT):
	$(Q)$(MAKECMD) PROJ_EXT_LONGNAME=$(shell if readlink $(MAIN_DIR)/proj.release >/dev/null; then readlink -n $(MAIN_DIR)/proj.release ; else date '+%Y%m%d' ; fi).ext ext_build

.PHONY: ext_build
ext_build: $(EXTPACK_MD5)
	$(Q)mkdir -p $(SHIP_DIR)
	$(call RUN_CMD_TIMED,$(SHELL) $(HEX_SCRIPTSDIR)/makeextpack $(SHIP_DIR)/$(PROJ_EXT_LONGNAME) $(EXTPACK),"  GEN     $(PROJ_EXT_LONGNAME)")
	$(Q)ln -sf $(SHIP_DIR)/$(PROJ_EXT_LONGNAME) $(PROJ_EXT)
	$(Q)md5sum < $(PROJ_EXT) > $(SHIP_DIR)/$(PROJ_EXT_LONGNAME).md5
	$(Q)umount $(NAS) || true
	$(Q)rmdir $(NAS) || true

$(PROJ_PORTAL_EXT):
	$(Q)$(MAKECMD) PROJ_PORTAL_EXT_LONGNAME=$(shell if readlink $(MAIN_DIR)/proj.release >/dev/null; then readlink -n $(MAIN_DIR)/proj.release ; else date '+%Y%m%d' ; fi).portal.ext portal_ext_build

.PHONY: portal_ext_build
portal_ext_build: $(NAS)
	$(Q)mkdir -p $(SHIP_DIR)
	$(call RUN_CMD_TIMED,$(SHELL) $(HEX_SCRIPTSDIR)/makeextpack $(SHIP_DIR)/$(PROJ_PORTAL_EXT_LONGNAME) $(PORTALPACK),"  GEN     $(PROJ_PORTAL_EXT_LONGNAME)")
	$(Q)ln -sf $(SHIP_DIR)/$(PROJ_PORTAL_EXT_LONGNAME) $(PROJ_PORTAL_EXT)
	$(Q)md5sum < $(PROJ_PORTAL_EXT) > $(SHIP_DIR)/$(PROJ_PORTAL_EXT_LONGNAME).md5
	$(Q)umount $(NAS) || true
	$(Q)rmdir $(NAS) || true

clean::
	$(Q)umount $(NAS) || true
	$(Q)rmdir $(NAS) || true

include $(HEX_MAKEDIR)/hex_sdk.mk
