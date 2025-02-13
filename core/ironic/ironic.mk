# Cube SDK
# ironic installation

IRONIC_CONF_DIR := /etc/ironic
IRONIC_INSP_CONF_DIR := /etc/ironic-inspector

ROOTFS_DNF += tftp-server
ROOTFS_DNF_NOARCH += openstack-ironic-api openstack-ironic-conductor openstack-ironic-inspector openstack-ironic-inspector-api openstack-ironic-inspector-conductor openstack-ironic-inspector-dnsmasq openstack-ironic-ui
ROOTFS_DNF_NOARCH += python3-networking-baremetal python3-ironic-neutron-agent python3-dracclient python3-scciclient python3-sushy syslinux-tftpboot

rootfs_install::
	$(Q)mkdir -p $(ROOTDIR)/tftpboot/pxelinux.cfg $(ROOTDIR)/tftpboot/images
	$(Q)chroot $(ROOTDIR) chown -R ironic /tftpboot
	$(Q)cp -f $(ROOTDIR)/$(IRONIC_CONF_DIR)/ironic.conf $(ROOTDIR)/$(IRONIC_CONF_DIR)/ironic.conf.def
	$(Q)cp -f $(ROOTDIR)/$(IRONIC_INSP_CONF_DIR)/inspector.conf $(ROOTDIR)/$(IRONIC_INSP_CONF_DIR)/inspector.conf.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/ironic/openstack-ironic-inspector-dnsmasq.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/ironic/openstack-ironic-file-server.service ./lib/systemd/system