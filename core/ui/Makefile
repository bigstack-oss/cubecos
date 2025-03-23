# Cube SDK

include ../../build.mk

# ui artifacts
UI_VERSION :=
UI_BUILD_NUMBER :=

UI_GIT_DIR := ./git
UI_RPMBUILD_DIR := $(TOP_BLDDIR)/core/ui/rpmbuild
UI_TARBALL = $(UI_RPMBUILD_DIR)/SOURCES/cube-cos-ui-$(UI_VERSION).tar.gz
UI_SPEC_FILE := $(UI_RPMBUILD_DIR)/SPECS/cube-cos-ui.spec
UI_RPM_BUILD = $(UI_RPMBUILD_DIR)/RPMS/x86_64/cube-cos-ui-$(UI_VERSION)-1.el9.$(UI_BUILD_NUMBER).x86_64.rpm
UI_RPM := $(TOP_BLDDIR)/core/ui/ui.rpm

# clean up the environment
.PHONY: ui_build_prep
ui_build_prep:
	$(Q)rm -rf $(UI_GIT_DIR)
	$(Q)rm -rf $(UI_RPMBUILD_DIR)

# prepare the ui source code, being pulled from GitHub using the default branch
$(UI_GIT_DIR):
	$(Q)mkdir $(UI_GIT_DIR)
	$(call RUN_CMD_TIMED, \
		for i in {1..10} ; do \
		timeout 30 git clone --depth 1 https://github.com/bigstack-oss/cube-cos-ui.git $(UI_GIT_DIR) && break ; \
		done,\
		"  CLONE   github.com/bigstack-oss/cube-cos-ui.git")
	$(Q)$(eval UI_VERSION=`cd $(UI_GIT_DIR) && node -p "require('./packages/cube-frontend-web-app/package.json').version"`)
	$(Q)$(eval UI_BUILD_NUMBER=`cd $(UI_GIT_DIR) && git rev-parse --short HEAD`)

# prepare the rpm build directory
$(UI_RPMBUILD_DIR):
	$(Q)mkdir $(UI_RPMBUILD_DIR)
	$(Q)cd $(UI_RPMBUILD_DIR) && mkdir BUILD RPMS SOURCES SPECS SRPMS

# make the source tarball
$(UI_TARBALL): $(UI_RPMBUILD_DIR) $(UI_GIT_DIR)
	$(Q)mkdir ./source
	$(Q)mkdir -p ./source/packages/cube-frontend-api
	$(Q)cp -r \
		$(UI_GIT_DIR)/packages/cube-frontend-api/package.json \
		$(UI_GIT_DIR)/packages/cube-frontend-api/tsconfig.json \
		./source/packages/cube-frontend-api
	$(Q)mkdir -p ./source/packages/cube-frontend-api/sdk
	$(Q)cp \
		$(UI_GIT_DIR)/packages/cube-frontend-api/sdk/api.ts \
		$(UI_GIT_DIR)/packages/cube-frontend-api/sdk/base.ts \
		$(UI_GIT_DIR)/packages/cube-frontend-api/sdk/common.ts \
		$(UI_GIT_DIR)/packages/cube-frontend-api/sdk/configuration.ts \
		$(UI_GIT_DIR)/packages/cube-frontend-api/sdk/index.ts \
		./source/packages/cube-frontend-api/sdk
	$(Q)mkdir -p ./source/packages/cube-frontend-ui-library
	$(Q)cp -r \
		$(UI_GIT_DIR)/packages/cube-frontend-ui-library/src \
		$(UI_GIT_DIR)/packages/cube-frontend-ui-library/package.json \
		$(UI_GIT_DIR)/packages/cube-frontend-ui-library/postcss.config.js \
		$(UI_GIT_DIR)/packages/cube-frontend-ui-library/tailwind.config.js \
		$(UI_GIT_DIR)/packages/cube-frontend-ui-library/tsconfig.json \
		$(UI_GIT_DIR)/packages/cube-frontend-ui-library/vite.config.ts \
		./source/packages/cube-frontend-ui-library
	$(Q)mkdir -p ./source/packages/cube-frontend-ui-theme
	$(Q)cp -r \
		$(UI_GIT_DIR)/packages/cube-frontend-ui-theme/src \
		$(UI_GIT_DIR)/packages/cube-frontend-ui-theme/package.json \
		$(UI_GIT_DIR)/packages/cube-frontend-ui-theme/tsconfig.json \
		./source/packages/cube-frontend-ui-theme
	$(Q)mkdir -p ./source/packages/cube-frontend-utils
	$(Q)cp -r \
		$(UI_GIT_DIR)/packages/cube-frontend-utils/src \
		$(UI_GIT_DIR)/packages/cube-frontend-utils/package.json \
		$(UI_GIT_DIR)/packages/cube-frontend-utils/tsconfig.json \
		./source/packages/cube-frontend-utils
	$(Q)mkdir -p ./source/packages/cube-frontend-web-app
	$(Q)cp -r \
		$(UI_GIT_DIR)/packages/cube-frontend-web-app/public \
		$(UI_GIT_DIR)/packages/cube-frontend-web-app/src \
		$(UI_GIT_DIR)/packages/cube-frontend-web-app/index.html \
		$(UI_GIT_DIR)/packages/cube-frontend-web-app/package.json \
		$(UI_GIT_DIR)/packages/cube-frontend-web-app/postcss.config.js \
		$(UI_GIT_DIR)/packages/cube-frontend-web-app/tailwind.config.js \
		$(UI_GIT_DIR)/packages/cube-frontend-web-app/tsconfig.app.json \
		$(UI_GIT_DIR)/packages/cube-frontend-web-app/tsconfig.json \
		$(UI_GIT_DIR)/packages/cube-frontend-web-app/tsconfig.node.json \
		$(UI_GIT_DIR)/packages/cube-frontend-web-app/vite.config.ts \
		./source/packages/cube-frontend-web-app
	$(Q)cp -r \
		$(UI_GIT_DIR)/LICENSE \
		$(UI_GIT_DIR)/package.json \
		$(UI_GIT_DIR)/pnpm-lock.yaml \
		$(UI_GIT_DIR)/pnpm-workspace.yaml \
		$(UI_GIT_DIR)/tsconfig.json \
		./source
	$(Q)tar -cvzf "cube-cos-ui-$(UI_VERSION).tar.gz" source 2>&1 > /dev/null
	$(Q)mv ./cube-cos-ui-$(UI_VERSION).tar.gz $(UI_RPMBUILD_DIR)/SOURCES
	$(Q)rm -r ./source

# prepare the rpm spec file
$(UI_SPEC_FILE): $(UI_RPMBUILD_DIR) $(UI_GIT_DIR)
	$(Q)cp $(UI_GIT_DIR)/packages/cube-frontend-web-app/cube-cos-ui.spec $(UI_RPMBUILD_DIR)/SPECS

# build the ui rpm package
$(UI_RPM_BUILD): $(UI_TARBALL) $(UI_SPEC_FILE)
	$(call RUN_CMD_TIMED, \
		nvm use $(UI_NODE_VERSION) && \
		rpmbuild -bb --nodeps --define "_topdir $(UI_RPMBUILD_DIR)" --define "version $(UI_VERSION)" --define "build_number $(UI_BUILD_NUMBER)" $(UI_SPEC_FILE), \
		"  BUILD   cube-cos-ui-$(UI_VERSION)-1.el9.$(UI_BUILD_NUMBER).x86_64.rpm")

# move the built rpm back to the local directory, and clean up the build environment
$(UI_RPM): ui_build_prep $(UI_RPM_BUILD)
	$(Q)cp -f $(UI_RPM_BUILD) ./ui.rpm

BUILD += $(UI_RPM)
BUILDCLEAN += $(UI_RPM) $(UI_RPMBUILD_DIR) $(UI_GIT_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
