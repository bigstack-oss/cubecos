# Cube SDK
# web installation

#$(PROJ_HEAVYFS): $(CORE_WEBAPPDIR)/gencerts.sh $(CORE_WEBAPPDIR)/selfsign.cnf

rootfs_install::
	$(Q)wget -qO- --no-check-certificate https://nodejs.org/download/release/$(NODE_VERSION)/node-$(NODE_VERSION)-linux-x64.tar.xz | tar -xJ --strip-components=1 -C $(ROOTDIR)/usr/local/
#	$(Q)cp -r $(CORE_WEBAPPDIR)/gencerts.sh $(ROOTDIR)/var/www
#	$(Q)cp -r $(CORE_WEBAPPDIR)/selfsign.cnf $(ROOTDIR)/var/www

# Add lmi source
LMI_DIR := $(CORE_WEBAPPDIR)/lmi
LMI_SRC := $(shell find $(LMI_DIR) -type f 2>/dev/null)

$(PROJ_HEAVYFS): $(LMI_SRC)

rootfs_install::
	# Assure lmi static files are properly installed
	$(Q)mkdir -p $(ROOTDIR)/var/www/lmi/static
	$(Q)mkdir -p $(ROOTDIR)/var/www/lmi/api
	$(Q)mkdir -p $(ROOTDIR)/var/www/lmi/config-server
	$(Q)cp -rf $(LMI_DIR)/static/* $(ROOTDIR)/var/www/lmi/static
	$(Q)cp -rf $(LMI_DIR)/api/* $(ROOTDIR)/var/www/lmi/api
	$(Q)cp -rf $(LMI_DIR)/config-server/* $(ROOTDIR)/var/www/lmi/config-server
	$(Q)cp -rf $(LMI_DIR)/.env.example $(ROOTDIR)/var/www/lmi/.env.example
	# Assure lmi client and server app are properly installed
	$(Q)cp -rf $(TOP_BLDDIR)/core/webapp/lmi/srclinks/.next $(ROOTDIR)/var/www/lmi/
	$(Q)cp -rf $(TOP_BLDDIR)/core/webapp/lmi/srclinks/node_modules $(ROOTDIR)/var/www/lmi/
	$(Q)cp -f $(LMI_DIR)/server.js $(ROOTDIR)/var/www/lmi/
	# Force the file permissions to be the same (rw-r--r--) and user/group to www-data
	$(Q)chroot $(ROOTDIR) chown -R www-data:www-data /var/www/lmi
	$(Q)chroot $(ROOTDIR) find /var/www/lmi -type d -exec chmod 755 {} +
	$(Q)chroot $(ROOTDIR) find /var/www/lmi -type f -exec chmod 644 {} +
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(CORE_WEBAPPDIR)/lmi.service ./lib/systemd/system
