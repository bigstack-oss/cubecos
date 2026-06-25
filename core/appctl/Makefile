# Cube SDK

include ../../build.mk
APPCTL_RPM := appctl.rpm
PKG_NAME := cube-cos-app-framework
GITHUB_URL := https://github.com/bigstack-oss/$(PKG_NAME)

ifneq ($(RC),)
$(APPCTL_RPM):
	$(call RUN_CMD_TIMED, \
		wget -O appctl.rpm $(GITHUB_URL)/releases/download/v3.1.0-rc3/$(PKG_NAME)-v3.1.0-1.fc35.0751aad.x86_64.rpm, \
		"  PULL    $(APPCTL_RPM)")
else
GIT_DIR := git
RPMBUILD_DIR := rpmbuild
RPMBUILD_SPECS := $(RPMBUILD_DIR)/SPECS
RPMBUILD_SOURCES := $(RPMBUILD_DIR)/SOURCES
RPMBUILD_RPMS := $(RPMBUILD_DIR)/RPMS

# prepare the appctl source code, being pulled from GitHub using the default branch
# For RC: git clone -b v3.1.0-rc3
$(GIT_DIR):
	$(call RUN_CMD_TIMED, \
		for i in {1..3} ; do \
		rm -fr $@ && timeout 120 git clone --depth 1 $(GITHUB_URL).git $@ && break ; \
		done,\
		"  CLONE   $(GITHUB_URL)")
	$(Q)cd $@ && git lfs pull

version: $(GIT_DIR)
	$(Q)head -n 1 $(GIT_DIR)/VERSION > version

build_number: $(GIT_DIR)
	$(Q)cd $(GIT_DIR) && \
		git rev-parse --short HEAD > ../build_number

# prepare the rpm build directory
$(RPMBUILD_DIR):
	$(Q)mkdir $(RPMBUILD_DIR)
	$(Q)cd $(RPMBUILD_DIR) && mkdir BUILD SRPMS SPECS

# make the source tarball
# RPMBUILD_DIR order-only: rule writes rpmbuild/SOURCES.tgz into it (bumps dir mtime).
$(RPMBUILD_SOURCES): $(GIT_DIR) version | $(RPMBUILD_DIR)
	$(Q)mkdir ./source
	$(Q)cp -r $(GIT_DIR)/.git/ ./source/
	$(Q)cd ./source && git checkout . $(QEND)
	$(Q)sudo rm -r ./source/.git/ ./source/.github/
	$(Q)tar -cvzf $@.tgz source $(QEND) || tar -cvzf $@.tgz source $(QEND)
	$(Q)mkdir -p $(RPMBUILD_DIR)/SOURCES
	$(Q)mv $@.tgz $(RPMBUILD_DIR)/SOURCES/$(PKG_NAME)-`cat version`.tar.gz
	$(Q)rm -r ./source

# build the appctl rpm package
$(RPMBUILD_RPMS): $(RPMBUILD_SOURCES) build_number
	$(Q)cp $(GIT_DIR)/init/$(PKG_NAME).spec $(RPMBUILD_DIR)/SPECS/
	$(Q)mkdir -p $(RPMBUILD_DIR)/RPMS/x86_64
	$(call RUN_CMD_TIMED, \
		rpmbuild -bb --nodeps --define "_topdir $(CURDIR)/$(RPMBUILD_DIR)" --define "version `cat version`" --define "build_number `cat build_number`" $(RPMBUILD_SPECS)/$(PKG_NAME).spec,\
		"  BUILD   $(PKG_NAME)-`cat version`-1.el9.`cat build_number`.x86_64.rpm")
	$(Q)touch $@

# move the built rpm back to the local directory
$(APPCTL_RPM): $(RPMBUILD_RPMS)
	$(Q)cp -f $</x86_64/$(PKG_NAME)-`cat version`-1.el9.`cat build_number`.x86_64.rpm $@
	$(Q)cp -rf $(GIT_DIR)/plugins ./plugins
endif

copy-source-eol-image:
	$(call RUN_CMD_TIMED, sh -x $(COREDIR)/appctl/copy-images.sh $(COREDIR)/appctl/images/tars,"  COPY    appctl eol image")

.PHONY: copy-image
copy-image: copy-source-eol-image
	$(call RUN_CMD_TIMED, sh -x $(COREDIR)/docker/copy-images.sh $(shell cat $(COREDIR)/appctl/images/list.txt),"  COPY    appctl image")

BUILD += $(APPCTL_RPM)
BUILDCLEAN += $(APPCTL_RPM) $(RPMBUILD_DIR) $(GIT_DIR) version build_number source $(PKG_NAME)-$(APPCTL_VERSION).tar.gz plugins

include $(HEX_MAKEDIR)/hex_sdk.mk
