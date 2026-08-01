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

AMPHORA := $(TOP_BLDDIR)/../amphora-x64-haproxy_antelope.qcow2
MANILA  := $(TOP_BLDDIR)/../manila-service-image_antelope.qcow2
RANCHER := $(TOP_BLDDIR)/../rancher-cluster-image-rke2-v1.32.4.raw
EXTPACK := $(AMPHORA) $(MANILA) $(RANCHER)
EXTPACK_MD5 := $(shell for E in $(EXTPACK); do echo $${E}.md5 ; done)

PROJ_PORTAL_EXT := $(MAIN_DIR)/proj.portal.ext
PKGCLEAN += $(PROJ_PORTAL_EXT)
PORTALPACK ?= $(NAS)/cloud-image/ubuntu_24.04.qcow2 \
$(NAS)/cloud-image/centos_10.qcow2 \
$(NAS)/cloud-image/debian_12.qcow2 \
$(NAS)/cloud-image/rocky_9.qcow2

$(NAS):
	$(Q)[ -d $@ ] || mkdir -p $@
	$(Q)mount -o ro $(PROJ_NFS_SERVER):$(PROJ_NFS_OPENSTACK_PATH)/ $@

$(AMPHORA): $(NAS)
	$(Q)cp $</app-image/antelope/amphora-x64-haproxy_antelope.qcow2 $@

.PHONY: $(AMPHORA).md5
$(AMPHORA).md5: $(AMPHORA)
	$(Q)diff $@ $(NAS)/app-image/antelope/amphora-x64-haproxy_antelope.qcow2.md5 2>/dev/null || ( cp -f $(NAS)/app-image/antelope/amphora-x64-haproxy_antelope.qcow2 $< && md5sum $< | awk '{print $$1}' > $@ )

$(MANILA): $(NAS)
	$(Q)cp $</app-image/antelope/manila-service-image_antelope.qcow2 $@

.PHONY: $(MANILA).md5
$(MANILA).md5: $(MANILA)
	$(Q)diff $@ $(NAS)/app-image/antelope/manila-service-image_antelope.qcow2.md5 2>/dev/null || ( cp -f $(NAS)/app-image/antelope/manila-service-image_antelope.qcow2 $< && md5sum $< | awk '{print $$1}' > $@ )

$(RANCHER): $(NAS)
	$(Q)cp $</app-image/yoga/rancher-cluster-image-rke2-v1.32.4.raw $@

.PHONY: $(RANCHER).md5
$(RANCHER).md5: $(RANCHER)
	$(Q)diff $@ $(NAS)/app-image/yoga/rancher-cluster-image-rke2-v1.32.4.raw.md5 2>/dev/null || ( cp -f $(NAS)/app-image/yoga/rancher-cluster-image-rke2-v1.32.4.raw $< && md5sum $< | awk '{print $$1}' > $@ )

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
	$(Q)nohup md5sum < $(PROJ_EXT) > $(SHIP_DIR)/$(PROJ_EXT_LONGNAME).md5 2>&1 &
	$(Q)nohup sha256sum < $(PROJ_EXT) > $(SHIP_DIR)/$(PROJ_EXT_LONGNAME).sha256 2>&1 &
	$(Q)umount $(NAS) || true
	$(Q)rmdir $(NAS) || true

$(PROJ_PORTAL_EXT):
	$(Q)$(MAKECMD) PROJ_PORTAL_EXT_LONGNAME=$(shell if readlink $(MAIN_DIR)/proj.release >/dev/null; then readlink -n $(MAIN_DIR)/proj.release ; else date '+%Y%m%d' ; fi).portal.ext portal_ext_build

.PHONY: portal_ext_build
portal_ext_build: $(NAS)
	$(Q)mkdir -p $(SHIP_DIR)
	$(call RUN_CMD_TIMED,$(SHELL) $(HEX_SCRIPTSDIR)/makeextpack $(SHIP_DIR)/$(PROJ_PORTAL_EXT_LONGNAME) $(PORTALPACK),"  GEN     $(PROJ_PORTAL_EXT_LONGNAME)")
	$(Q)ln -sf $(SHIP_DIR)/$(PROJ_PORTAL_EXT_LONGNAME) $(PROJ_PORTAL_EXT)
	$(Q)nohup md5sum < $(PROJ_PORTAL_EXT) > $(SHIP_DIR)/$(PROJ_PORTAL_EXT_LONGNAME).md5 2>&1 &
	$(Q)nohup sha256sum < $(PROJ_PORTAL_EXT) > $(SHIP_DIR)/$(PROJ_PORTAL_EXT_LONGNAME).sha256 2>&1 &
	$(Q)umount $(NAS) || true
	$(Q)rmdir $(NAS) || true

clean::
	$(Q)umount $(NAS) || true
	$(Q)rmdir $(NAS) || true

include $(HEX_MAKEDIR)/hex_sdk.mk
