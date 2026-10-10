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

AMPHORA := $(TOP_BLDDIR)/../amphora-x64-haproxy_epoxy.qcow2
MANILA  := $(TOP_BLDDIR)/../manila-service-image_epoxy.qcow2
RANCHER_SRC := app-image/yoga/rancher-cluster-image-rke2-v1.32.4.raw
# The "_<ver>" suffix is what os_extpack_image_import strips to name the glance image.
RANCHER := $(TOP_BLDDIR)/../rancher-cluster-image-rke2-v1.32.4_v1.32.4-rke2r1.qcow2
RANCHER_VERSION := $(shell sed -n 's/^APP_VERSION := //p' $(COREDIR)/rancher/Makefile)
RANCHER_AGENT := $(TOP_BLDDIR)/core/rancher/registry-rancher-agent_v$(RANCHER_VERSION).tar
EXTPACK_MD5 := $(AMPHORA).md5 $(MANILA).md5 $(RANCHER).md5
EXTPACK := $(AMPHORA) $(MANILA) $(RANCHER) $(RANCHER_AGENT)

PROJ_PORTAL_EXT := $(MAIN_DIR)/proj.portal.ext
PKGCLEAN += $(PROJ_PORTAL_EXT)
PORTALPACK ?= $(NAS)/cloud-image/ubuntu_24.04.qcow2 \
$(NAS)/cloud-image/centos_10.qcow2 \
$(NAS)/cloud-image/debian_12.qcow2 \
$(NAS)/cloud-image/rocky_9.qcow2

$(NAS):
	$(Q)[ -d $@ ] || mkdir -p $@
	$(Q)mount -o ro $(PROJ_NFS_SERVER):$(PROJ_NFS_OPENSTACK_PATH)/ $@

# The amphora image follows the venv, so it moved to app-image/caracal/ with #640 and
# moves to app-image/epoxy/ with #667, rebuilt on ubuntu noble, the base the 2025.1
# diskimage-create.sh defaults to.
# Unlike the manila service image this really is an octavia rebuild -- the guest runs
# the amphora agent, which speaks a versioned REST API to the controllers and so has
# to be the same release they are (core/octavia/Makefile builds it from the
# OCTAVIA_VER tag for exactly that reason).
# Its .md5 sidecar on the NAS has to be the *bare hash*, i.e.
# `md5sum <file> | awk '{print $$1}'`: the diff below compares this file byte for
# byte, so a full-format `md5sum` line never matches and silently re-copies ~340 MB
# over NFS on every build.
$(AMPHORA): $(NAS)
	$(Q)cp $</app-image/epoxy/amphora-x64-haproxy_epoxy.qcow2 $@

.PHONY: $(AMPHORA).md5
$(AMPHORA).md5: $(AMPHORA)
	$(Q)diff $@ $(NAS)/app-image/epoxy/amphora-x64-haproxy_epoxy.qcow2.md5 2>/dev/null || ( cp -f $(NAS)/app-image/epoxy/amphora-x64-haproxy_epoxy.qcow2 $< && md5sum $< | awk '{print $$1}' > $@ )

# The manila service image follows the venv, so it moved to app-image/caracal/ with
# #638 and moves to app-image/epoxy/ with #664. The artifact is a base-OS refresh, not
# a manila rebuild -- the guest runs nfs-kernel-server and samba, never manila -- but it
# is versioned by the release it ships with, the way the amphora and rancher images are.
# Its .md5 sidecar on the NAS has to be the *bare hash*, i.e.
# `md5sum <file> | awk '{print $$1}'`: the diff below compares this file byte for byte,
# so a full-format `md5sum` line never matches and silently re-copies ~1 GB over NFS on
# every build.
$(MANILA): $(NAS)
	$(Q)cp $</app-image/epoxy/manila-service-image_epoxy.qcow2 $@

.PHONY: $(MANILA).md5
$(MANILA).md5: $(MANILA)
	$(Q)diff $@ $(NAS)/app-image/epoxy/manila-service-image_epoxy.qcow2.md5 2>/dev/null || ( cp -f $(NAS)/app-image/epoxy/manila-service-image_epoxy.qcow2 $< && md5sum $< | awk '{print $$1}' > $@ )

# The NAS raw is a fully allocated 40 GiB disk; ship it as compressed qcow2 (~4.3 GiB),
# which the import converts back to raw. Here the .md5 holds the NAS raw's hash, so the
# conversion reruns only when the source changes.
.PHONY: $(RANCHER).md5
$(RANCHER).md5: $(NAS)
	$(Q)( [ -s $(RANCHER) ] && diff -q $@ $(NAS)/$(RANCHER_SRC).md5 >/dev/null 2>&1 ) || \
		( qemu-img convert -c -O qcow2 $(NAS)/$(RANCHER_SRC) $(RANCHER).tmp && \
		  mv -f $(RANCHER).tmp $(RANCHER) && cp -f $(NAS)/$(RANCHER_SRC).md5 $@ )

.PHONY: $(RANCHER_AGENT)
$(RANCHER_AGENT):
	$(Q)make -C ../rancher $(notdir $@)

.PHONY: ext
ext: $(PROJ_EXT) $(PROJ_PORTAL_EXT)
	@true

# Create extention package
$(PROJ_EXT):
	$(Q)$(MAKECMD) PROJ_EXT_LONGNAME=$(shell if readlink $(MAIN_DIR)/proj.release >/dev/null; then readlink -n $(MAIN_DIR)/proj.release ; else date '+%Y%m%d' ; fi).ext ext_build

.PHONY: ext_build
ext_build: $(EXTPACK_MD5) $(RANCHER_AGENT)
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
