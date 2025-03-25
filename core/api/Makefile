# Cube SDK

include ../../build.mk
include version
include build_number

# api binary
API_GIT_DIR := ./git
API_RPMBUILD_DIR := $(TOP_BLDDIR)/core/api/rpmbuild
API_TARBALL := $(API_RPMBUILD_DIR)/SOURCES/cube-cos-api-$(API_VERSION).tar.gz
API_SPEC_FILE := $(API_RPMBUILD_DIR)/SPECS/cube-cos-api.spec
API_RPM_BUILD := $(API_RPMBUILD_DIR)/RPMS/x86_64/cube-cos-api-$(API_VERSION)-1.el9.$(API_BUILD_NUMBER).x86_64.rpm
API_RPM := $(TOP_BLDDIR)/core/api/api.rpm

# prepare the api source code, being pulled from GitHub using the default branch
$(API_GIT_DIR):
	$(Q)mkdir $(API_GIT_DIR)
	$(call RUN_CMD_TIMED, \
		for i in {1..10} ; do \
		timeout 30 git clone --depth 1 https://github.com/bigstack-oss/cube-cos-api.git $(API_GIT_DIR) && break ; \
		done,\
		"  CLONE   github.com/bigstack-oss/cube-cos-api.git")

version: $(API_GIT_DIR)
	$(Q)echo -n "API_VERSION := " > version
	$(Q)head -n 1 $(API_GIT_DIR)/VERSION >> version

build_number: $(API_GIT_DIR)
	$(Q)echo -n "API_BUILD_NUMBER := " > build_number
	$(Q)cd $(API_GIT_DIR) && \
		git rev-parse --short HEAD >> ../build_number

# prepare the rpm build directory
$(API_RPMBUILD_DIR):
	$(Q)mkdir $(API_RPMBUILD_DIR)
	$(Q)cd $(API_RPMBUILD_DIR) && mkdir BUILD RPMS SOURCES SPECS SRPMS

# make the source tarball
$(API_TARBALL): $(API_RPMBUILD_DIR) $(API_GIT_DIR)
	$(Q)mkdir ./source
	$(Q)cp -r \
		$(API_GIT_DIR)/api \
		$(API_GIT_DIR)/cmd \
		$(API_GIT_DIR)/internal \
		$(API_GIT_DIR)/configs \
		$(API_GIT_DIR)/init \
		$(API_GIT_DIR)/go.mod \
		$(API_GIT_DIR)/go.sum \
		$(API_GIT_DIR)/LICENSE \
		./source
	$(Q)tar -cvzf "cube-cos-api-$(API_VERSION).tar.gz" source 2>&1 > /dev/null
	$(Q)mv ./cube-cos-api-$(API_VERSION).tar.gz $(API_RPMBUILD_DIR)/SOURCES
	$(Q)rm -r ./source

# prepare the rpm spec file
$(API_SPEC_FILE): $(API_RPMBUILD_DIR) $(API_GIT_DIR)
	$(Q)cp $(API_GIT_DIR)/init/cube-cos-api.spec $(API_RPMBUILD_DIR)/SPECS

# build the api rpm package
$(API_RPM_BUILD): $(API_TARBALL) $(API_SPEC_FILE)
	$(call RUN_CMD_TIMED, \
		rpmbuild -bb --nodeps --define "_topdir $(API_RPMBUILD_DIR)" --define "version $(API_VERSION)" --define "build_number $(API_BUILD_NUMBER)" $(API_SPEC_FILE),\
		"  BUILD   cube-cos-api-$(API_VERSION)-1.el9.$(API_BUILD_NUMBER).x86_64.rpm")

# move the built rpm back to the local directory
$(API_RPM): $(API_RPM_BUILD)
	$(Q)cp -f $(API_RPM_BUILD) ./api.rpm

BUILD += $(API_RPM)
BUILDCLEAN += $(API_RPM) $(API_RPMBUILD_DIR) $(API_GIT_DIR) version build_number

include $(HEX_MAKEDIR)/hex_sdk.mk
