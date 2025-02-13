# Cube SDK
# keystone installation

ROOTFS_DNF += httpd python3-mod_wsgi mod_ssl mod_auth_mellon
ROOTFS_DNF_NOARCH += openstack-keystone

KEYSTONE_CONF_DIR := /etc/keystone

rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/keystone-wsgi.conf.in ./etc/httpd/conf.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/idp_mapping_rules.json ./etc/keystone/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/v3_mellon_keycloak_master.conf.def ./etc/httpd/conf.d/
	$(Q)sed "s/    CustomLog .* combined//" $(ROOTDIR)/etc/httpd/conf/httpd.conf > $(ROOTDIR)/etc/httpd/conf/httpd.conf.orig
	$(Q)cp -f $(ROOTDIR)/etc/keystone/keystone.conf $(ROOTDIR)/etc/keystone/keystone.conf.def
	$(Q)[ -f $(ROOTDIR)/etc/httpd/conf.d/ssl.conf ] && mv $(ROOTDIR)/etc/httpd/conf.d/ssl.conf $(ROOTDIR)/etc/httpd/conf.d/ssl.conf.orig || /bin/true
# openssl 3.x requires no /dev/urandom for the written openssl command
	$(Q)sed -i '/RANDFILE/d' $(ROOTDIR)/usr/libexec/mod_auth_mellon/mellon_create_metadata.sh
