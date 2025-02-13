# CUBE SDK

include ../../build.mk

OVN_REPO := centos-release-nfv-openvswitch
OVN_PREFIX := ovn23.03
OVN_DST := ovn-23.03.0
OVN_SRPM := https://cbs.centos.org/kojifiles/packages/ovn23.03/23.03.0/69.el9s/src/ovn23.03-23.03.0-69.el9s.src.rpm

RPMBUILD_DIR := /root/rpmbuild
OVN_PATCHDIR := $(COREDIR)/neutron/ovn_patch/$(HEX_DIST)

# http://bradthemad.org/tech/notes/patching_rpms.php

ovn-northd:
	$(call RUN_CMD_TIMED,dnf -y install $(OVN_REPO) python3-sphinx autoconf automake desktop-file-utils graphviz libcap-ng-devel libtool python3-pyOpenSSL unbound-devel tcpdump,"  PREP    rpmbuild")
#	$(call RUN_CMD_TIMED,dnf download $(OVN_PREFIX)-central --source,"  DL      $(OVN_PREFIX).src.rpm")
	$(call RUN_CMD_TIMED,wget $(OVN_SRPM),"  DL      $(OVN_PREFIX).src.rpm")
	$(Q)rm -rf $(RPMBUILD_DIR)
	$(call RUN_CMD_TIMED,rpm -ivh *.src.rpm,"  INS     $(OVN_PREFIX).src.rpm")
	$(Q)cp -f $(OVN_PATCHDIR)/0001-northd-remove-dr-snat-high-priority.patch $(RPMBUILD_DIR)/SOURCES
	$(Q)cp -f $(OVN_PATCHDIR)/$(OVN_PREFIX).spec $(RPMBUILD_DIR)/SPECS
	$(call RUN_CMD_TIMED,cd $(RPMBUILD_DIR) && rpmbuild -ba SPECS/$(OVN_PREFIX).spec || /bin/true,"  BLD     $(OVN_PREFIX)")
	$(Q)cp -f $(RPMBUILD_DIR)/BUILD/$(OVN_DST)/northd/ovn-northd ./

FULL += ovn-northd
PKGCLEAN += ovn-northd

include $(HEX_MAKEDIR)/hex_sdk.mk
