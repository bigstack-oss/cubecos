# Cube SDK

include ../../build.mk

# api binary
API_VERSION :=
API_BUILD_NUMBER :=

API_GIT_DIR := /root/api
API_TARBALL = $(RPMBUILD_DIR)/SOURCES/cube-cos-api-$(API_VERSION).tar.gz
API_SPEC_FILE := $(RPMBUILD_DIR)/SPECS/cube-cos-api.spec
API_RPM_BUILD = $(RPMBUILD_DIR)/RPMS/x86_64/cube-cos-api-$(API_VERSION)-1.el9.$(API_BUILD_NUMBER).x86_64.rpm
API_RPM := $(TOP_BLDDIR)/core/api/api.rpm

# clean up the environment
.PHONY: api_build_prep
api_build_prep:
	$(Q)rm -rf $(API_GIT_DIR)
	$(Q)rm -rf $(RPMBUILD_DIR)

# prepare the api source code, being pulled from GitHub using the default branch
$(API_GIT_DIR):
	$(Q)mkdir $(API_GIT_DIR)
	$(call RUN_CMD_TIMED, \
		for i in {1..10} ; do \
		timeout 30 git clone --depth 1 https://github.com/bigstack-oss/cube-cos-api.git $(API_GIT_DIR) && break ; \
		done,\
		"  CLONE   github.com/bigstack-oss/cube-cos-api.git")
	$(Q)$(eval API_VERSION=`head -n 1 $(API_GIT_DIR)/VERSION`)
	$(Q)$(eval API_BUILD_NUMBER=`cd $(API_GIT_DIR) && git rev-parse --short HEAD`)

# prepare the rpm build directory
$(RPMBUILD_DIR):
	$(Q)mkdir /root/rpmbuild
	$(Q)cd /root/rpmbuild && mkdir BUILD RPMS SOURCES SPECS SRPMS

# make the source tarball
$(API_TARBALL): $(RPMBUILD_DIR) $(API_GIT_DIR)
	$(Q)mkdir /root/source
	$(Q)cp -r \
		$(API_GIT_DIR)/api \
		$(API_GIT_DIR)/cmd \
		$(API_GIT_DIR)/internal \
		$(API_GIT_DIR)/configs \
		$(API_GIT_DIR)/init \
		$(API_GIT_DIR)/go.mod \
		$(API_GIT_DIR)/go.sum \
		$(API_GIT_DIR)/LICENSE \
		/root/source
	$(Q)cd /root && tar -cvzf "cube-cos-api-$(API_VERSION).tar.gz" source 2>&1 > /dev/null
	$(Q)mv "/root/cube-cos-api-$(API_VERSION).tar.gz" $(RPMBUILD_DIR)/SOURCES
	$(Q)rm -r /root/source

# prepare the rpm spec file
$(API_SPEC_FILE): $(RPMBUILD_DIR) $(API_GIT_DIR)
	$(Q)cp $(API_GIT_DIR)/init/cube-cos-api.spec $(RPMBUILD_DIR)/SPECS

# build the api rpm package
$(API_RPM_BUILD): $(API_TARBALL) $(API_SPEC_FILE)
	$(call RUN_CMD_TIMED, \
		rpmbuild -bb --nodeps --define "version $(API_VERSION)" --define "build_number $(API_BUILD_NUMBER)" $(API_SPEC_FILE),\
		"  BUILD   cube-cos-api-$(API_VERSION)-1.el9.$(API_BUILD_NUMBER).x86_64.rpm")

# move the built rpm back to the local directory, and clean up the build environment
$(API_RPM): api_build_prep $(API_RPM_BUILD)
	$(Q)cp -f $(API_RPM_BUILD) ./api.rpm

BUILD += $(API_RPM)
BUILDCLEAN += $(API_RPM) $(API_GIT_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
