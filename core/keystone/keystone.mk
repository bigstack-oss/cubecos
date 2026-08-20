# Cube SDK
# keystone installation

# python3-mod_wsgi is gone: horizon was the last in-process wsgi application, and
# #609 moved it behind a gunicorn socket like keystone, barbican, placement and
# monasca-api already were. Nothing under /etc/httpd/conf.d carries a WSGI
# directive any more, so httpd starts without the module.
# mod_ssl and mod_auth_mellon for the SAML2 integration with Keycloak as IDP
ROOTFS_DNF += httpd mod_ssl mod_auth_mellon openldap-devel

KEYSTONE_CONF_DIR := /etc/keystone

# keystone runs out of the caracal venv, not the antelope one it shared with every
# other 2023.1 service. keystone 25.0.0 pulls oslo.db 15, oslo.messaging 14.7 and
# SQLAlchemy 2.x; installing that beside nova/neutron/cinder would have upgraded the
# whole antelope dependency set under them, so the identity service moves alone into
# /opt/openstack-caracal instead (skyline was the first occupant, this is the second).
# Resolved against os-caracal-pip-upper-constraints.txt the two sets are disjoint --
# keystone adds 51 packages there and changes no version skyline already holds.
KEYSTONE_VENV_SITE_PACKAGES := $(CARACAL_OPENSTACK_HOME_DIR)/lib/python$(CARACAL_PYTHON_VER)/site-packages

# install keystone
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(CARACAL_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			keystone==25.0.0 \
			python-keystoneclient \
			PyMySQL \
			"oslo.messaging[kafka]" \
			python-ldap \
			ldappool \
			python-memcached \
			gunicorn"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/keystone-manage /usr/bin/keystone-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/keystone-status /usr/bin/keystone-status
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/keystone-wsgi-admin /usr/bin/keystone-wsgi-admin
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/keystone-wsgi-public /usr/bin/keystone-wsgi-public

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/keystone
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/keystone

# generate default configs
rootfs_install::
	$(Q)cp -f $(COREDIR)/keystone/config-generator.conf $(ROOTDIR)/tmp/keystone/
	$(Q)cp -f $(COREDIR)/keystone/keystone.conf.sample $(ROOTDIR)/tmp/keystone/
	$(Q)cp -f $(COREDIR)/keystone/keystone-schema.yaml $(ROOTDIR)/tmp/keystone/
	$(Q)cp -f $(COREDIR)/keystone/keystone-schema.json $(ROOTDIR)/tmp/keystone/
	$(Q)cp -f $(COREDIR)/keystone/policy.json $(ROOTDIR)/tmp/keystone/
	$(Q)cp -f $(COREDIR)/keystone/logging.conf.sample $(ROOTDIR)/tmp/keystone/
	$(Q)cp -f $(COREDIR)/keystone/default_catalog.templates $(ROOTDIR)/tmp/keystone/
	$(Q)cp -f $(COREDIR)/keystone/sso_callback_template.html $(ROOTDIR)/tmp/keystone/

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
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/keystone/keystone-schema.yaml /usr/share/keystone/keystone-schema.yaml
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/keystone/keystone-schema.json /usr/share/keystone/keystone-schema.json
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/keystone
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/log/keystone
	$(Q)chroot $(ROOTDIR) touch /var/log/keystone/keystone.log

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

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/keystone

# install custom files
rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/keystone-wsgi.conf.in ./etc/httpd/conf.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/v3_mellon_keycloak_master.conf.def ./etc/httpd/conf.d/
	$(Q)sed "s/    CustomLog .* combined//" $(ROOTDIR)/etc/httpd/conf/httpd.conf > $(ROOTDIR)/etc/httpd/conf/httpd.conf.orig
	$(Q)[ -f $(ROOTDIR)/etc/httpd/conf.d/ssl.conf ] && mv $(ROOTDIR)/etc/httpd/conf.d/ssl.conf $(ROOTDIR)/etc/httpd/conf.d/ssl.conf.orig || /bin/true
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/ssl.conf ./etc/httpd/conf.d/
# httpd ships a default welcome page; drop the config and its html so port 8080
# serves no default content (cubecos-private#76)
	$(Q)[ -f $(ROOTDIR)/etc/httpd/conf.d/welcome.conf ] && mv $(ROOTDIR)/etc/httpd/conf.d/welcome.conf $(ROOTDIR)/etc/httpd/conf.d/welcome.conf.orig || /bin/true
	$(Q)rm -rf $(ROOTDIR)/usr/share/httpd/noindex
# openssl 3.x requires no /dev/urandom for the written openssl command
	$(Q)sed -i '/RANDFILE/d' $(ROOTDIR)/usr/libexec/mod_auth_mellon/mellon_create_metadata.sh
	$(Q)cp -f $(ROOTDIR)/etc/keystone/keystone.conf $(ROOTDIR)/etc/keystone/keystone.conf.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/idp_mapping_rules.json ./etc/keystone/
	$(Q)chroot $(ROOTDIR) chown keystone:apache /var/lib/keystone
	$(Q)chroot $(ROOTDIR) chmod 770 /var/lib/keystone
	$(Q)cp -f $(COREDIR)/keystone/gunicorn.py $(ROOTDIR)$(CARACAL_OPENSTACK_HOME_DIR)/bin/keystone-gunicorn.py
	$(Q)chroot $(ROOTDIR) chown root:root $(CARACAL_OPENSTACK_HOME_DIR)/bin/keystone-gunicorn.py
	$(Q)chroot $(ROOTDIR) chmod 644 $(CARACAL_OPENSTACK_HOME_DIR)/bin/keystone-gunicorn.py
	$(Q)# openstack-keystone.service names this module, not keystone's own wsgi entry
	$(Q)# point. It goes in site-packages rather than beside the gunicorn config
	$(Q)# because that is what is importable: gunicorn resolves the application
	$(Q)# string on sys.path, and /var/lib/keystone (WorkingDirectory) is group
	$(Q)# writable state, not somewhere to keep code that authenticates requests.
	$(Q)cp -f $(COREDIR)/keystone/cube_mellon_wsgi.py $(ROOTDIR)$(KEYSTONE_VENV_SITE_PACKAGES)/cube_mellon_wsgi.py
	$(Q)chroot $(ROOTDIR) chown root:root $(KEYSTONE_VENV_SITE_PACKAGES)/cube_mellon_wsgi.py
	$(Q)chroot $(ROOTDIR) chmod 644 $(KEYSTONE_VENV_SITE_PACKAGES)/cube_mellon_wsgi.py
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/keystone/openstack-keystone.service ./lib/systemd/system
