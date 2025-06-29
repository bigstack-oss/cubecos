# Cube SDK

include ../../build.mk
UI_RPM := ui.rpm

ifneq ($(RC),)
$(UI_RPM):
	$(call RUN_CMD_TIMED, \
		wget -O ui.rpm https://github.com/bigstack-oss/cube-cos-ui/releases/download/cube-cos-ui-v3.0.0-rc4/cube-cos-ui-3.0.0-1.cddd34e.x86_64.rpm, \
		"  PULL    $(UI_RPM)")
else
include version
include build_number

# ui artifacts
UI_GIT_DIR := ./git
UI_RPMBUILD_DIR := rpmbuild
UI_TARBALL := $(UI_RPMBUILD_DIR)/SOURCES/cube-cos-ui-$(UI_VERSION).tar.gz
UI_SPEC_FILE := $(UI_RPMBUILD_DIR)/SPECS/cube-cos-ui.spec
UI_RPM_BUILD := $(UI_RPMBUILD_DIR)/RPMS/x86_64/cube-cos-ui-$(UI_VERSION)-1.el9.$(UI_BUILD_NUMBER).x86_64.rpm

# prepare the ui source code, being pulled from GitHub using the default branch
# For RC: git clone -b v3.0.0-rc4
$(UI_GIT_DIR):
	$(Q)mkdir $(UI_GIT_DIR)
	$(call RUN_CMD_TIMED, \
		for i in {1..10} ; do \
		timeout 30 git clone --depth 1 https://github.com/bigstack-oss/cube-cos-ui.git $(UI_GIT_DIR) && break ; \
		done,\
		"  CLONE   github.com/bigstack-oss/cube-cos-ui.git")
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cd $(UI_GIT_DIR) && nvm install $(QEND)
	$(Q)cd $(UI_GIT_DIR) && nvm use $(QEND) && npm install -g pnpm@latest-10 $(QEND)
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV

version: $(UI_GIT_DIR)
	$(Q)echo -n "UI_VERSION := " > version
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cd $(UI_GIT_DIR) && \
		nvm use $(QEND) && \
		node -p "require('./packages/cube-frontend-web-app/package.json').version" >> ../version
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV

build_number: $(UI_GIT_DIR)
	$(Q)echo -n "UI_BUILD_NUMBER := " > build_number
	$(Q)cd $(UI_GIT_DIR) && \
		git rev-parse --short HEAD >> ../build_number

# prepare the rpm build directory
$(UI_RPMBUILD_DIR):
	$(Q)mkdir $(UI_RPMBUILD_DIR)
	$(Q)cd $(UI_RPMBUILD_DIR) && mkdir BUILD RPMS SOURCES SPECS SRPMS

# make the source tarball
$(UI_TARBALL): $(UI_RPMBUILD_DIR) $(UI_GIT_DIR)
	$(Q)mkdir ./source
	$(Q)cp -r $(UI_GIT_DIR)/.git/ ./source/
	$(Q)cd ./source && git checkout . $(QEND)
	$(Q)sudo rm -r ./source/.git/ ./source/.github/ ./source/.husky/ ./source/.vscode/
	$(Q)tar -cvzf "cube-cos-ui-$(UI_VERSION).tar.gz" source $(QEND)
	$(Q)mv ./cube-cos-ui-$(UI_VERSION).tar.gz $(UI_RPMBUILD_DIR)/SOURCES
	$(Q)rm -r ./source

# prepare the rpm spec file
$(UI_SPEC_FILE): $(UI_RPMBUILD_DIR) $(UI_GIT_DIR)
	$(Q)cp $(UI_GIT_DIR)/packages/cube-frontend-web-app/cube-cos-ui.spec $(UI_RPMBUILD_DIR)/SPECS

# build the ui rpm package
$(UI_RPM_BUILD): $(UI_TARBALL) $(UI_SPEC_FILE)
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(call RUN_CMD_TIMED, \
		cd $(UI_GIT_DIR) && \
		nvm use $(QEND) && \
		cd - && \
		rpmbuild -bb --nodeps --define "_topdir $(CURDIR)/$(UI_RPMBUILD_DIR)" --define "version $(UI_VERSION)" --define "build_number $(UI_BUILD_NUMBER)" $(UI_SPEC_FILE), \
		"  BUILD   cube-cos-ui-$(UI_VERSION)-1.el9.$(UI_BUILD_NUMBER).x86_64.rpm")
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV

# move the built rpm back to the local directory
$(UI_RPM): $(UI_RPM_BUILD)
	$(Q)cp -f $(UI_RPM_BUILD) ./ui.rpm
endif

BUILD += $(UI_RPM)
BUILDCLEAN += $(UI_RPM) $(UI_RPMBUILD_DIR) $(UI_GIT_DIR) version build_number

include $(HEX_MAKEDIR)/hex_sdk.mk
