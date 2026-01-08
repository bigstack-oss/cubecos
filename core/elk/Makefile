# CUBE SDK

include ../../build.mk

PKG_NAME     := opensearch-dashboards
PKG_VER      := 3.4.0
PKG_REL      := 1.patched
ARCH         := x86_64
ORIGIN_RPM   := $(PKG_NAME)-$(PKG_VER)-linux-x64.rpm
DOWNLOAD_URL := https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/$(PKG_VER)/$(ORIGIN_RPM)
NODE_VERSION := 20
TARGET_RPM   := $(PKG_NAME)-$(PKG_VER)-$(PKG_REL).$(ARCH).rpm

# Directories
RPMBUILD_DIR := rpmbuild
BUILD_ROOT   := $(RPMBUILD_DIR)/BUILDROOT
SOURCE_DIR   := $(RPMBUILD_DIR)/SOURCES
SPECS_DIR    := $(RPMBUILD_DIR)/SPECS
RPMS_DIR     := $(RPMBUILD_DIR)/RPMS

# Plugin Path
PLUGIN_PATH  := usr/share/opensearch-dashboards/plugins/reportsDashboards

# --- STAMP FILES (To track state) ---
STAMP_DIR      := $(RPMBUILD_DIR)/.stamps
STAMP_DOWNLOAD := $(STAMP_DIR)/download
STAMP_EXTRACT  := $(STAMP_DIR)/extract
STAMP_PATCH    := $(STAMP_DIR)/patch

$(STAMP_DIR):
	$(Q)mkdir -p $(RPMBUILD_DIR)/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
	$(Q)mkdir -p $(BUILD_ROOT)
	$(Q)mkdir -p $(STAMP_DIR)

$(STAMP_DOWNLOAD): | $(STAMP_DIR)
	$(call RUN_CMD_TIMED, \
		wget -c $(DOWNLOAD_URL) -O $(SOURCE_DIR)/original.rpm, \
		"  DWL     $(ORIGIN_RPM)")
	$(Q)touch $@

$(STAMP_EXTRACT): $(STAMP_DOWNLOAD)
	$(call RUN_CMD_TIMED, \
		rm -rf $(BUILD_ROOT) && mkdir -p $(BUILD_ROOT) && \
		cd $(BUILD_ROOT) && \
		rpm2cpio ../SOURCES/original.rpm | cpio -idm --quiet, \
		"  EXT     $(ORIGIN_RPM)")
	$(Q)touch $@

$(STAMP_PATCH): $(STAMP_EXTRACT)
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(call RUN_CMD_TIMED, \
		cd $(BUILD_ROOT)/$(PLUGIN_PATH) && \
		nvm install $(NODE_VERSION) && \
		nvm use $(NODE_VERSION) && \
		npm install -g yarn && \
		yarn add jspdf@4.0.0 && \
		yarn install --no-frozen-lockfile && \
		yarn install --production --no-frozen-lockfile --ignore-scripts && \
		rm -rf node_modules/.cache, \
		"  PATCH   jspdf@4.0.0")
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV
	$(Q)touch $@

# --- OFFICIAL-STYLE SPEC FILE ---
define SPEC_FILE_CONTENT
Name: $(PKG_NAME)
Version: $(PKG_VER)
Release: $(PKG_REL)
Summary: Patched OpenSearch Dashboards
License: Apache-2.0
AutoReqProv: no

%description
Patched version of OpenSearch Dashboards with jspdf fix.

# 1. PRE-INSTALL: Create User/Group
%pre
getent group opensearch-dashboards >/dev/null || groupadd -r opensearch-dashboards
getent passwd opensearch-dashboards >/dev/null || \
    useradd -r -g opensearch-dashboards -d /usr/share/opensearch-dashboards \
    -s /sbin/nologin -c "opensearch-dashboards user" opensearch-dashboards
exit 0

# 2. POST-INSTALL: Reload Systemd
%post
systemctl daemon-reload
if [ $$1 -eq 1 ]; then
    systemctl preset opensearch-dashboards.service >/dev/null 2>&1 || :
fi

# 3. PRE-UNINSTALL: Stop service
%preun
if [ $$1 -eq 0 ]; then
    systemctl --no-reload disable --now opensearch-dashboards.service >/dev/null 2>&1 || :
fi

%files
%defattr(-,root,root,-)
# App Files (Owned by User)
%attr(-,opensearch-dashboards,opensearch-dashboards) /usr/share/opensearch-dashboards

# Config Files (Marked so upgrades don't delete user changes)
%config(noreplace) /etc/opensearch-dashboards/opensearch_dashboards.yml
%attr(0755,opensearch-dashboards,opensearch-dashboards) /var/lib/opensearch-dashboards
%attr(0755,opensearch-dashboards,opensearch-dashboards) /var/log/opensearch-dashboards

# System Files (Owned by Root)
/usr/lib/systemd/system/opensearch-dashboards.service
/etc/opensearch-dashboards
/usr/share/opensearch-dashboards/bin/opensearch-dashboards
/usr/share/opensearch-dashboards/bin/opensearch-dashboards-plugin

/*
endef
export SPEC_FILE_CONTENT
# --- END SPEC ---

$(TARGET_RPM): $(STAMP_PATCH)
	$(Q)echo "$$SPEC_FILE_CONTENT" > $(SPECS_DIR)/$(PKG_NAME).spec
	$(call RUN_CMD_TIMED, \
		rpmbuild -bb \
		--define "_topdir $(CURDIR)/$(RPMBUILD_DIR)" \
		--define "buildroot $(CURDIR)/$(BUILD_ROOT)" \
		$(SPECS_DIR)/$(PKG_NAME).spec, \
		"  PACK    $(TARGET_RPM)")
	$(Q)mv $(RPMS_DIR)/$(ARCH)/$(PKG_NAME)-$(PKG_VER)-$(PKG_REL).$(ARCH).rpm .

dev-deploy:
	$(call RUN_CMD_TIMED, cd $(SRCDIR)/logstash && tar -cf - pipelines.yml patterns.txt eventdb conf.d | pigz -9 > logstash.tgz,"  GEN     logstash.tgz")
	$(call RUN_CMD_TIMED, cd $(SRCDIR)/logstash && scp logstash.tgz root@$(HOST):/etc/logstash,"  UPLOAD  logstash.tgz")
	$(Q)ssh root@$(HOST) rm -rf /etc/logstash/eventdb /etc/logstash/conf.d
	$(Q)ssh root@$(HOST) tar -I pigz -xf /etc/logstash/logstash.tgz -C /etc/logstash
	$(call RUN_CMD, ssh root@$(HOST) hex_config bootstrap logstash,"  RECFG   logstash")

BUILD += $(TARGET_RPM)
BUILDCLEAN += $(TARGET_RPM) $(RPMBUILD_DIR) $(SRCDIR)/logstash/logstash.tgz

include $(HEX_MAKEDIR)/hex_sdk.mk
