# CUBE SDK

include ../../build.mk

OVN_REPO := centos-release-nfv-openvswitch
OVN_PREFIX := ovn24.03
OVN_SRPM := https://cbs.centos.org/kojifiles/packages/ovn24.03/24.03.8/31.el9s/src/ovn24.03-24.03.8-31.el9s.src.rpm

RPMBUILD_DIR := /root/rpmbuild
OVN_PATCHDIR := $(COREDIR)/neutron/ovn_patch/$(HEX_DIST)

# http://bradthemad.org/tech/notes/patching_rpms.php

ovn-northd:
	$(call RUN_CMD_TIMED,dnf -y install $(OVN_REPO) dnf-plugins-core rpm-build,"  PREP    rpmbuild")
#	$(call RUN_CMD_TIMED,dnf download $(OVN_PREFIX)-central --source,"  DL      $(OVN_PREFIX).src.rpm")
	$(call RUN_CMD_TIMED,wget $(OVN_SRPM),"  PULL    $(OVN_PREFIX).src.rpm")
	$(Q)rm -rf $(RPMBUILD_DIR)
	$(call RUN_CMD_TIMED,rpm -ivh *.src.rpm,"  INSTALL $(OVN_PREFIX).src.rpm")
	$(Q)cp -f $(OVN_PATCHDIR)/0001-northd-remove-dr-snat-high-priority.patch $(RPMBUILD_DIR)/SOURCES/
	$(Q)cp -f $(OVN_PATCHDIR)/$(OVN_PREFIX).spec $(RPMBUILD_DIR)/SPECS/
	$(call RUN_CMD_TIMED,dnf -y builddep $(RPMBUILD_DIR)/SPECS/$(OVN_PREFIX).spec,"  DEP     $(OVN_PREFIX)")
	$(call RUN_CMD_TIMED,cd $(RPMBUILD_DIR) && rpmbuild -bc SPECS/$(OVN_PREFIX).spec,"  BUILD   $(OVN_PREFIX)")
	$(Q)cp -f $(RPMBUILD_DIR)/BUILD/ovn-*/northd/ovn-northd ./

FULL += ovn-northd
PKGCLEAN += ovn-northd
BUILDCLEAN += $(RPMBUILD_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
