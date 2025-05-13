# Cube SDK
# rancher installation
RANCHER_DIR := /opt/rancher/

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(RANCHER_DIR)
	$(Q)cp -f $(COREDIR)/rancher/clean-k8s.sh $(ROOTDIR)/$(RANCHER_DIR)
	$(Q)cp -f $(COREDIR)/rancher/rancher-images.txt $(ROOTDIR)/$(RANCHER_DIR)
	$(Q)cp -f $(COREDIR)/rancher/chart-values.yaml $(ROOTDIR)/$(RANCHER_DIR)
	$(Q)cp -f $(TOP_BLDDIR)/core/rancher/rancher-*.tgz $(ROOTDIR)/$(RANCHER_DIR)
	$(Q)cp -f $(TOP_BLDDIR)/core/rancher/rancher $(ROOTDIR)/usr/local/bin/
	$(Q)cp -rf $(TOP_BLDDIR)/core/rancher/nodedrivers/ $(ROOTDIR)/$(RANCHER_DIR)
	$(Q)chroot $(ROOTDIR) mkdir -p $(RANCHER_DIR)/cpo
	$(Q)cp -f $(TOP_BLDDIR)/core/rancher/cpo/*.tgz $(ROOTDIR)/$(RANCHER_DIR)/cpo/
# Use apache2 (httpd) to serve the node drivers
	$(Q)mkdir -p $(ROOTDIR)/var/www/html/static/ && \
		chroot $(ROOTDIR) ln -sf $(RANCHER_DIR)/nodedrivers/ /var/www/html/static/ && \
		chroot $(ROOTDIR) chown -R www-data:www-data /var/www/html
