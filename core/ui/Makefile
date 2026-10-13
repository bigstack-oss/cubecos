# Cube SDK

include ../../build.mk
UI_RPM := ui.rpm
PKG_NAME := cube-cos-ui
GITHUB_URL := https://github.com/bigstack-oss/$(PKG_NAME)
GITHUB_DL_URL := $(GITHUB_DL_BASE)/bigstack-oss/$(PKG_NAME)

# RC: download the pinned prebuilt rpm; otherwise build from $(CUBE_COS_UI_REF) (core/component-refs.mk)
ifneq ($(and $(RC),$(CUBE_COS_UI_RPM)),)
$(if $(CUBE_COS_UI_RPM_SHA256),,$(error CUBE_COS_UI_RPM is set but CUBE_COS_UI_RPM_SHA256 is not))
$(UI_RPM):
	$(call RUN_CMD_TIMED, \
		wget -O $@.part $(GITHUB_DL_URL)/releases/download/$(CUBE_COS_UI_RPM) && \
		echo "$(CUBE_COS_UI_RPM_SHA256)  $@.part" | sha256sum -c --quiet && mv -f $@.part $@, \
		"  PULL    $(CUBE_COS_UI_RPM)")
else
GIT_DIR := git
RPMBUILD_DIR := rpmbuild
RPMBUILD_SPECS := $(RPMBUILD_DIR)/SPECS
RPMBUILD_SOURCES := $(RPMBUILD_DIR)/SOURCES
RPMBUILD_RPMS := $(RPMBUILD_DIR)/RPMS

# clone the ui source at $(CUBE_COS_UI_REF) (core/component-refs.mk)
$(GIT_DIR):
	$(call RUN_CMD_TIMED, \
		for i in {1..3} ; do \
		rm -fr $@ && timeout 120 git clone --depth 1 -b $(CUBE_COS_UI_REF) $(GITHUB_URL).git $@ && break ; \
		done,\
		"  CLONE   $(GITHUB_URL)@$(CUBE_COS_UI_REF)")
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cd $@ && nvm install $(QEND)
	$(Q)cd $@ && nvm use $(QEND) && npm install -g pnpm@latest-10 $(QEND)
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV

version: $(GIT_DIR)
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cd $(GIT_DIR) && \
		nvm use $(QEND) && \
		node -p "require('./packages/cube-frontend-web-app/package.json').version" > ../version
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV

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
	$(Q)rm -r ./source/.git/ ./source/.github/ ./source/.husky/ ./source/.vscode/
	$(Q)tar -cvzf $@.tgz source $(QEND)
	$(Q)mkdir -p $(RPMBUILD_DIR)/SOURCES
	$(Q)mv $@.tgz $(RPMBUILD_DIR)/SOURCES/$(PKG_NAME)-`cat version`.tar.gz
	$(Q)rm -r ./source
	$(Q)touch $@

# build the ui rpm package
$(RPMBUILD_RPMS): $(RPMBUILD_SOURCES) build_number
	$(Q)cp $(GIT_DIR)/packages/cube-frontend-web-app/$(PKG_NAME).spec $(RPMBUILD_DIR)/SPECS/
	$(Q)mkdir -p $(RPMBUILD_DIR)/RPMS/x86_64
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(call RUN_CMD_TIMED, \
		cd $(GIT_DIR) && \
		nvm use $(QEND) && \
		cd - && \
		rpmbuild -bb --nodeps --define "_topdir $(CURDIR)/$(RPMBUILD_DIR)" --define "version `cat version`" --define "build_number `cat build_number`"  $(RPMBUILD_DIR)/SPECS/$(PKG_NAME).spec, \
		"  BUILD   $(PKG_NAME)-`cat version`-1.el9.`cat build_number`.x86_64.rpm")
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV
	$(Q)touch $@

# move the built rpm back to the local directory
$(UI_RPM): $(RPMBUILD_RPMS)
	$(Q)cp -f $</x86_64/$(PKG_NAME)-`cat version`-1.el9.`cat build_number`.x86_64.rpm $@
endif

BUILD += $(UI_RPM)
BUILDCLEAN += $(UI_RPM) $(RPMBUILD_DIR) $(GIT_DIR) version build_number

include $(HEX_MAKEDIR)/hex_sdk.mk
