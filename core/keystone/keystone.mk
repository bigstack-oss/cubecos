# Cube SDK
# keystone installation

ROOTFS_DNF += httpd python3-mod_wsgi mod_ssl mod_auth_mellon

KEYSTONE_CONF_DIR := /etc/keystone

# install keystone
rootfs_install::
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) keystone==23.0.2"

rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/keystone-wsgi.conf.in ./etc/httpd/conf.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/idp_mapping_rules.json ./etc/keystone/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/v3_mellon_keycloak_master.conf.def ./etc/httpd/conf.d/
	$(Q)sed "s/    CustomLog .* combined//" $(ROOTDIR)/etc/httpd/conf/httpd.conf > $(ROOTDIR)/etc/httpd/conf/httpd.conf.orig
	$(Q)cp -f $(ROOTDIR)/etc/keystone/keystone.conf $(ROOTDIR)/etc/keystone/keystone.conf.def
	$(Q)[ -f $(ROOTDIR)/etc/httpd/conf.d/ssl.conf ] && mv $(ROOTDIR)/etc/httpd/conf.d/ssl.conf $(ROOTDIR)/etc/httpd/conf.d/ssl.conf.orig || /bin/true
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/ssl.conf ./etc/httpd/conf.d/
# openssl 3.x requires no /dev/urandom for the written openssl command
	$(Q)sed -i '/RANDFILE/d' $(ROOTDIR)/usr/libexec/mod_auth_mellon/mellon_create_metadata.sh
