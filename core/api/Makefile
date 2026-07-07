# Cube SDK

include ../../build.mk
API_RPM := api.rpm
PKG_NAME := cube-cos-api
GITHUB_URL := https://github.com/bigstack-oss/cube-cos-api

ifneq ($(RC),)
$(API_RPM):
	$(call RUN_CMD_TIMED, \
		wget -O api.rpm $(GITHUB_URL)/releases/download/v3.1.0-rc3/cube-cos-api-v3.1.0-1.fc35.5310e06.x86_64.rpm, \
		"  PULL    $(API_RPM)")
else
GIT_DIR := git
RPMBUILD_DIR := rpmbuild
RPMBUILD_SPECS := $(RPMBUILD_DIR)/SPECS
RPMBUILD_SOURCES := $(RPMBUILD_DIR)/SOURCES
RPMBUILD_RPMS := $(RPMBUILD_DIR)/RPMS

# prepare the api source code, being pulled from GitHub using the default branch
# For RC: git clone -b v3.1.0-rc3
$(GIT_DIR):
	$(call RUN_CMD_TIMED, \
		for i in {1..3} ; do \
		rm -fr $@ && timeout 120 git clone --depth 1 $(GITHUB_URL).git $@ && break ; \
		done,\
		"  CLONE   $(GITHUB_URL)")

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
# RPMBUILD_DIR is order-only (|): the rule writes rpmbuild/SOURCES.tgz into it,
# bumping the dir's mtime every build, which would otherwise rebuild SOURCES forever.
$(RPMBUILD_SOURCES): $(GIT_DIR) version | $(RPMBUILD_DIR)
	$(Q)mkdir ./source
	$(Q)cp -r $(GIT_DIR)/.git/ ./source/
	$(Q)cd ./source && git checkout . $(QEND)
	$(Q)rm -r ./source/.git/ ./source/.github/ ./source/.gitignore
	$(Q)tar -cvzf $@.tgz source $(QEND)
	$(Q)mkdir -p $(RPMBUILD_DIR)/SOURCES
	$(Q)mv $@.tgz $(RPMBUILD_DIR)/SOURCES/$(PKG_NAME)-`cat version`.tar.gz
	$(Q)rm -r ./source
	$(Q)touch $@

# build the api rpm package
$(RPMBUILD_RPMS): $(RPMBUILD_SOURCES) build_number
	$(Q)cp $(GIT_DIR)/init/$(PKG_NAME).spec $(RPMBUILD_DIR)/SPECS/
	$(call RUN_CMD_TIMED, \
		rpmbuild -bb --nodeps --define "_topdir $(CURDIR)/$(RPMBUILD_DIR)" --define "version `cat version`" --define "build_number `cat build_number`" $(RPMBUILD_DIR)/SPECS/$(PKG_NAME).spec,\
		"  BUILD   $(PKG_NAME)-`cat version`-1.el9.`cat build_number`.x86_64.rpm")
	$(Q)touch $@

# move the built rpm back to the local directory
$(API_RPM): $(RPMBUILD_RPMS)
	$(Q)cp -f $</x86_64/$(PKG_NAME)-`cat version`-1.el9.`cat build_number`.x86_64.rpm $@
endif

BUILD += $(API_RPM)
BUILDCLEAN += $(API_RPM) $(RPMBUILD_DIR) $(GIT_DIR) version build_number

include $(HEX_MAKEDIR)/hex_sdk.mk
