# Cube SDK
# neutron installation

RDOOVN_VERSION := -23.03-3.el9s
ROOTFS_DNF += openvswitch3.1 ovn23.03 ovn23.03-central ovn23.03-host
ROOTFS_DNF_DL_FROM += https://cbs.centos.org/kojifiles/packages/rdo-openvswitch/3.1/3.el9s/noarch/rdo-ovn$(RDOOVN_VERSION).noarch.rpm
ROOTFS_DNF_DL_FROM += https://cbs.centos.org/kojifiles/packages/rdo-openvswitch/3.1/3.el9s/noarch/rdo-ovn-central$(RDOOVN_VERSION).noarch.rpm
ROOTFS_DNF_DL_FROM += https://cbs.centos.org/kojifiles/packages/rdo-openvswitch/3.1/3.el9s/noarch/rdo-ovn-host$(RDOOVN_VERSION).noarch.rpm
NEUTRON_SRCDIR := $(ROOTDIR)/usr/lib/python$(PYTHON_VER)/site-packages/neutron

ROOTFS_DNF += libreswan
ROOTFS_DNF_NOARCH += openstack-neutron openstack-neutron-ml2 python3-networking-ovn python3-networking-ovn-metadata-agent

NEUTRON_CONFDIR := $(ROOTDIR)/etc/neutron

OVN_PATCHDIR := $(COREDIR)/neutron/ovn_patch/$(HEX_DIST)

ROOTFS_PIP_DL_FROM += https://github.com/bigstack-oss/neutron-vpnaas.git
ROOTFS_PIP_DL_FROM += https://github.com/openstack/neutron-vpnaas-dashboard.git

NEUTRON_PATCHDIR := $(COREDIR)/neutron/$(OPENSTACK_RELEASE)_patch

rootfs_install::
	$(Q)cp -f $(PIPS_DIR)/neutron-vpnaas-dashboard.git/neutron_vpnaas_dashboard/enabled/_7100*.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
	$(Q)chroot $(ROOTDIR) ln -sf /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
	$(Q)chroot $(ROOTDIR) ln -sf /etc/neutron/neutron_vpnaas.conf /usr/share/neutron/server/neutron_vpnaas.conf
	$(Q)chroot $(ROOTDIR) ln -sf /usr/local/bin/neutron-vpn-netns-wrapper /usr/sbin/neutron-vpn-netns-wrapper
	$(Q)cp -f $(NEUTRON_CONFDIR)/neutron.conf $(NEUTRON_CONFDIR)/neutron.conf.def
	$(Q)cp -f $(NEUTRON_CONFDIR)/plugins/ml2/ml2_conf.ini $(NEUTRON_CONFDIR)/plugins/ml2/ml2_conf.ini.def
	$(Q)cp -f $(NEUTRON_CONFDIR)/neutron_ovn_metadata_agent.ini $(NEUTRON_CONFDIR)/plugins/networking-ovn/networking-ovn-metadata-agent.ini.def
	$(Q)echo "neutron ALL = (root) NOPASSWD: /bin/privsep-helper" >> $(ROOTDIR)/etc/sudoers.d/neutron
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/neutron/neutron_vpnaas.conf ./etc/neutron/neutron_vpnaas.conf.def
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/neutron/vpn_agent.ini ./etc/neutron/vpn_agent.ini.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/neutron/ovn-plugin.filters ./usr/share/neutron/rootwrap/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/neutron/vpnaas.filters ./usr/share/neutron/rootwrap/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/neutron/neutron-ovn-vpn-agent.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/neutron/ovn-controller.service ./lib/systemd/system
	$(Q)$(INSTALL_PROGRAM) $(ROOTDIR) $(OVN_PATCHDIR)/ovn-northd ./usr/bin/

rootfs_install::
	$(Q)[ -d $(NEUTRON_PATCHDIR) ] && cp -rf $(NEUTRON_PATCHDIR)/* $(NEUTRON_SRCDIR)/ || /bin/true

rootfs_install::
	$(Q)for ns in $$(find $(ROOTDIR)/usr/lib/systemd/system/*neutron*.service) ; do sed -i /^Timeout*/d $$ns ; done
