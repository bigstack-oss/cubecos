# Cube SDK

include ../../build.mk
APPCTL_RPM := appctl.rpm

ifneq ($(RC),)
$(APPCTL_RPM):
	$(call RUN_CMD_TIMED, \
		wget -O appctl.rpm https://github.com/bigstack-oss/cube-cos-app-framework/releases/download/v3.0.0-rc4/cube-cos-app-framework-v0.0.1-1.fc35.7619a7f.x86_64.rpm, \
		"  PULL    $(APPCTL_RPM)")
else
include version
include build_number

# appctl binary
APPCTL_GIT_DIR := ./git_appctl
APPCTL_RPMBUILD_DIR := rpmbuild
APPCTL_TARBALL := $(APPCTL_RPMBUILD_DIR)/SOURCES/cube-cos-app-framework-$(APPCTL_VERSION).tar.gz
APPCTL_SPEC_FILE := $(APPCTL_RPMBUILD_DIR)/SPECS/cube-cos-app-framework.spec
APPCTL_RPM_BUILD := $(APPCTL_RPMBUILD_DIR)/RPMS/x86_64/cube-cos-app-framework-$(APPCTL_VERSION)-1.el9.$(APPCTL_BUILD_NUMBER).x86_64.rpm

# prepare the appctl source code, being pulled from GitHub using the default branch
# For RC: git clone -b v3.0.0-rc4
$(APPCTL_GIT_DIR):
	$(Q)rm -rf $(APPCTL_GIT_DIR)
	$(Q)mkdir $(APPCTL_GIT_DIR)
	$(call RUN_CMD_TIMED, \
		for i in {1..10} ; do \
		timeout 30 git clone --depth 1 https://github.com/bigstack-oss/cube-cos-app-framework.git $(APPCTL_GIT_DIR) && break ; \
		done,\
		"  CLONE   github.com/bigstack-oss/cube-cos-app-framework.git")
	$(Q)cd $(APPCTL_GIT_DIR) && git lfs pull

version: $(APPCTL_GIT_DIR)
	$(Q)echo -n "APPCTL_VERSION := " > version
	$(Q)head -n 1 $(APPCTL_GIT_DIR)/VERSION >> version

build_number: $(APPCTL_GIT_DIR)
	$(Q)echo -n "APPCTL_BUILD_NUMBER := " > build_number
	$(Q)cd $(APPCTL_GIT_DIR) && \
		git rev-parse --short HEAD >> ../build_number

# prepare the rpm build directory
$(APPCTL_RPMBUILD_DIR):
	$(Q)mkdir $(APPCTL_RPMBUILD_DIR)
	$(Q)cd $(APPCTL_RPMBUILD_DIR) && mkdir BUILD RPMS SOURCES SPECS SRPMS

# make the source tarball
$(APPCTL_TARBALL): $(APPCTL_RPMBUILD_DIR) $(APPCTL_GIT_DIR)
	$(Q)mkdir ./source_appctl
	$(Q)cp -r $(APPCTL_GIT_DIR)/.git/ ./source_appctl/
	$(Q)cd ./source_appctl && git checkout . $(QEND)
	$(Q)sudo rm -r ./source_appctl/.git/ ./source_appctl/.github/
	$(Q)tar -cvzf "cube-cos-app-framework-$(APPCTL_VERSION).tar.gz" source $(QEND)
	$(Q)mv ./cube-cos-app-framework-$(APPCTL_VERSION).tar.gz $(APPCTL_RPMBUILD_DIR)/SOURCES
	$(Q)rm -r ./source_appctl

# prepare the rpm spec file
$(APPCTL_SPEC_FILE): $(APPCTL_RPMBUILD_DIR) $(APPCTL_GIT_DIR)
	$(Q)cp $(APPCTL_GIT_DIR)/init/cube-cos-app-framework.spec $(APPCTL_RPMBUILD_DIR)/SPECS/

# build the appctl rpm package
$(APPCTL_RPM_BUILD): $(APPCTL_TARBALL) $(APPCTL_SPEC_FILE)
	$(call RUN_CMD_TIMED, \
		rpmbuild -bb --nodeps --define "_topdir $(CURDIR)/$(APPCTL_RPMBUILD_DIR)" --define "version $(APPCTL_VERSION)" --define "build_number $(APPCTL_BUILD_NUMBER)" $(APPCTL_SPEC_FILE),\
		"  BUILD   cube-cos-app-framework-$(APPCTL_VERSION)-1.el9.$(APPCTL_BUILD_NUMBER).x86_64.rpm")

# move the built rpm back to the local directory
$(APPCTL_RPM): $(APPCTL_RPM_BUILD)
	$(Q)cp -f $(APPCTL_RPM_BUILD) ./appctl.rpm
	$(Q)cp -f $(APPCTL_GIT_DIR)/plugins ./plugins
endif

copy-source-eol-image:
	$(call RUN_CMD_TIMED, sh -x $(COREDIR)/appctl/copy-images.sh $(APPCTL_GIT_DIR)/plugins/images/tars,"  COPY    appctl image")

.PHONY: copy-image
copy-image: copy-source-eol-image
	$(call RUN_CMD_TIMED, sh -x $(COREDIR)/docker/copy-images.sh $(shell cat $(APPCTL_GIT_DIR)/plugins/images/list.txt),"  COPY    appctl image")

BUILD += $(APPCTL_RPM)
BUILDCLEAN += $(APPCTL_RPM) $(APPCTL_RPMBUILD_DIR) $(APPCTL_GIT_DIR) version build_number

include $(HEX_MAKEDIR)/hex_sdk.mk
