# Cube SDK

include ../../build.mk
UI_RPM := ui.rpm
PKG_NAME := cube-cos-ui
GITHUB_URL := https://github.com/bigstack-oss/$(PKG_NAME)

ifneq ($(RC),)
$(UI_RPM):
	$(call RUN_CMD_TIMED, \
		wget -O ui.rpm $(GITHUB_URL)/releases/download/$(PKG_NAME)-v3.1.0-rc1/$(PKG_NAME)-3.1.0-1.96de32d.x86_64.rpm, \
		"  PULL    $(UI_RPM)")
else
GIT_DIR := git
RPMBUILD_DIR := rpmbuild
RPMBUILD_SPECS := $(RPMBUILD_DIR)/SPECS
RPMBUILD_SOURCES := $(RPMBUILD_DIR)/SOURCES
RPMBUILD_RPMS := $(RPMBUILD_DIR)/RPMS

# prepare the ui source code, being pulled from GitHub using the default branch
# For RC: git clone -b v3.1.0-rc1
$(GIT_DIR):
	$(call RUN_CMD_TIMED, \
		for i in {1..10} ; do \
		rm -fr $@ && timeout 30 git clone --depth 1 $(GITHUB_URL).git $@ && break ; \
		done,\
		"  CLONE   $(GITHUB_URL)")
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
		node -p "require('./packages/cube-frontend-web-app/package.json').version" >> ../version
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV

build_number: $(GIT_DIR)
	$(Q)cd $(GIT_DIR) && \
		git rev-parse --short HEAD >> ../build_number

# prepare the rpm build directory
$(RPMBUILD_DIR):
	$(Q)mkdir $(RPMBUILD_DIR)
	$(Q)cd $(RPMBUILD_DIR) && mkdir BUILD SRPMS SPECS

# make the source tarball
$(RPMBUILD_SOURCES): $(RPMBUILD_DIR) $(GIT_DIR) version
	$(Q)mkdir ./source
	$(Q)cp -r $(GIT_DIR)/.git/ ./source/
	$(Q)cd ./source && git checkout . $(QEND)
	$(Q)sudo rm -r ./source/.git/ ./source/.github/ ./source/.husky/ ./source/.vscode/
	$(Q)tar -cvzf $@.tgz source $(QEND)
	$(Q)mkdir -p $(RPMBUILD_DIR)/SOURCES
	$(Q)mv $@.tgz $(RPMBUILD_DIR)/SOURCES/$(PKG_NAME)-`cat version`.tar.gz
	$(Q)rm -r ./source

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
