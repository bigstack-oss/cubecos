# Cube SDK
# octavia installation

OCTAVIA_CONF_DIR := /etc/octavia

ROOTFS_DNF_NOARCH += openstack-octavia-api openstack-octavia-worker openstack-octavia-housekeeping openstack-octavia-health-manager openstack-octavia-ui

rootfs_install::
	$(Q)cp -f $(ROOTDIR)/$(OCTAVIA_CONF_DIR)/octavia.conf $(ROOTDIR)/$(OCTAVIA_CONF_DIR)/octavia.conf.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/octavia/certs/create_certificates.sh .$(OCTAVIA_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/octavia/certs/octavia-certs.cnf .$(OCTAVIA_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/octavia/dhclient.conf .$(OCTAVIA_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/octavia/octavia-worker.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/octavia/octavia-health-manager.service ./lib/systemd/system
	$(Q)chroot $(ROOTDIR) chmod 755 /etc/octavia/create_certificates.sh
