# Cube SDK
# keystone installation

ROOTFS_DNF += httpd python3-mod_wsgi mod_ssl mod_auth_mellon

KEYSTONE_CONF_DIR := /etc/keystone

# install keystone
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			keystone==23.0.2 \
			python-keystoneclient \
			PyMySQL \
			python-ldap \
			ldappool \
			python-memcached"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/keystone
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/keystone

# generate default configs
rootfs_install::
	$(Q)cp -f $(COREDIR)/keystone/config-generator.conf $(ROOTDIR)/tmp/keystone/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		oslo-config-generator \
			--config-file=/tmp/keystone/config-generator.conf \
			--output-file=/tmp/keystone/keystone.conf.sample"
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		oslo-config-generator \
			--config-file=/tmp/keystone/config-generator.conf \
			--format yaml \
			--output-file=/tmp/keystone/kestone-schema.yaml"
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		oslo-config-generator \
			--config-file=/tmp/keystone/config-generator.conf \
			--format json \
			--output-file=/tmp/keystone/kestone-schema.json"
	$(Q)chroot $(ROOTDIR) bash -c "echo \"{}\" > /tmp/keystone/policy.json"
	$(Q)cp -f $(COREDIR)/keystone/logging.conf.sample $(ROOTDIR)/tmp/keystone/
	$(Q)cp -f $(COREDIR)/keystone/default_catalog.templates $(ROOTDIR)/tmp/keystone/
	$(Q)cp -f $(COREDIR)/keystone/sso_callback_template.html $(ROOTDIR)/tmp/keystone/
	$(Q)cp -f $(COREDIR)/keystone/openstack-keystone.logrotate $(ROOTDIR)/tmp/keystone/
	$(Q)cp -f $(COREDIR)/keystone/openstack-keystone.sysctl $(ROOTDIR)/tmp/keystone/

# install system directories and files
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/keystone
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/keystone/policy.d
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/keystone/keystone.conf.sample /etc/keystone/keystone.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/keystone/policy.json /etc/keystone/policy.json
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/keystone/logging.conf.sample /etc/keystone/logging.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/keystone/default_catalog.templates /etc/keystone/default_catalog.templates
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/keystone/sso_callback_template.html /etc/keystone/sso_callback_template.html
	$(Q)chroot $(ROOTDIR) install -d -m 755 /usr/share/keystone
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/keystone/kestone-schema.yaml /usr/share/keystone/keystone-schema.yaml
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/keystone/kestone-schema.json /usr/share/keystone/keystone-schema.json
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/keystone/openstack-keystone.logrotate /etc/logrotate.d/openstack-keystone
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/keystone
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/log/keystone
	$(Q)chroot $(ROOTDIR) touch /var/log/keystone/keystone.log
	$(Q)chroot $(ROOTDIR) install -d -m 755 /lib/sysctl.d
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/keystone/openstack-keystone.sysctl /lib/sysctl.d/openstack-keystone.conf

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chmod 0644 /usr/share/keystone/keystone-schema.yaml
	$(Q)chroot $(ROOTDIR) chown root:keystone /usr/share/keystone/keystone-schema.yaml
	$(Q)chroot $(ROOTDIR) chmod 0644 /usr/share/keystone/keystone-schema.json
	$(Q)chroot $(ROOTDIR) chown root:keystone /usr/share/keystone/keystone-schema.json
	$(Q)chroot $(ROOTDIR) chmod 0750 /etc/keystone
	$(Q)chroot $(ROOTDIR) chown root:keystone /etc/keystone
	$(Q)chroot $(ROOTDIR) chmod 0750 /etc/keystone/policy.d
	$(Q)chroot $(ROOTDIR) chown root:keystone /etc/keystone/policy.d
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/keystone/keystone.conf
	$(Q)chroot $(ROOTDIR) chown root:keystone /etc/keystone/keystone.conf
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/keystone/logging.conf
	$(Q)chroot $(ROOTDIR) chown root:keystone /etc/keystone/logging.conf
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/keystone/policy.json
	$(Q)chroot $(ROOTDIR) chown root:keystone /etc/keystone/policy.json
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/keystone/default_catalog.templates
	$(Q)chroot $(ROOTDIR) chown root:keystone /etc/keystone/default_catalog.templates
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/keystone/sso_callback_template.html
	$(Q)chroot $(ROOTDIR) chown keystone:keystone /etc/keystone/sso_callback_template.html
	$(Q)chroot $(ROOTDIR) chown keystone:keystone /var/lib/keystone
	$(Q)chroot $(ROOTDIR) chmod 0750 /var/log/keystone
	$(Q)chroot $(ROOTDIR) chown keystone:keystone /var/log/keystone
	$(Q)chroot $(ROOTDIR) chmod 0660 /var/log/keystone/keystone.log
	$(Q)chroot $(ROOTDIR) chown root:keystone /var/log/keystone/keystone.log

# run some actions
rootfs_install::
	$(Q)chroot $(ROOTDIR) sysctl -p /lib/sysctl.d/openstack-keystone.conf

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/keystone

# install custom files
rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/keystone-wsgi.conf.in ./etc/httpd/conf.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/idp_mapping_rules.json ./etc/keystone/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/v3_mellon_keycloak_master.conf.def ./etc/httpd/conf.d/
	$(Q)sed "s/    CustomLog .* combined//" $(ROOTDIR)/etc/httpd/conf/httpd.conf > $(ROOTDIR)/etc/httpd/conf/httpd.conf.orig
	$(Q)cp -f $(ROOTDIR)/etc/keystone/keystone.conf $(ROOTDIR)/etc/keystone/keystone.conf.def
	$(Q)[ -f $(ROOTDIR)/etc/httpd/conf.d/ssl.conf ] && mv $(ROOTDIR)/etc/httpd/conf.d/ssl.conf $(ROOTDIR)/etc/httpd/conf.d/ssl.conf.orig || /bin/true
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/ssl.conf ./etc/httpd/conf.d/
# httpd ships a default welcome page; drop the config and its html so port 8080
# serves no default content (cubecos-private#76)
	$(Q)[ -f $(ROOTDIR)/etc/httpd/conf.d/welcome.conf ] && mv $(ROOTDIR)/etc/httpd/conf.d/welcome.conf $(ROOTDIR)/etc/httpd/conf.d/welcome.conf.orig || /bin/true
	$(Q)rm -rf $(ROOTDIR)/usr/share/httpd/noindex
# openssl 3.x requires no /dev/urandom for the written openssl command
	$(Q)sed -i '/RANDFILE/d' $(ROOTDIR)/usr/libexec/mod_auth_mellon/mellon_create_metadata.sh
