# Cube SDK
# barbican installation

BARBICAN_CONFDIR := $(ROOTDIR)/etc/barbican

# barbican runs out of the caracal venv, not the antelope one it shared with every other
# openstack service. 18.0.0 is the 2024.1 release (verified as the newest tag that is an
# ancestor of upstream's unmaintained/2024.1; 19.0.0 has already diverged onto 2024.2), and
# it needs python 3.11, so the service moves into $(CARACAL_OPENSTACK_HOME_DIR) -- skyline
# was the first occupant, then keystone, glance, cinder, nova/placement and neutron.
#
# PyKMIP: the kmip_secret_store plugin imports it unconditionally, oslo-config-generator
#   fails without it even when the plugin is unused. Still true in 18.0.0 -- the
#   kmip_plugin entry point and the barbican.plugin.secret_store.kmip generator namespace
#   both survive the hop.
# PyMySQL: config_barbican.cpp writes a mysql+pymysql:// connection URI
# oslo.messaging[kafka]: config_barbican.cpp points the notification transport at kafka
# python-keystoneclient / gunicorn: keystone.mk already installs both into this venv, but
#   they stay named here for the same reason the two above do -- a dependency nothing asks
#   for is one that disappears silently, and keystone is free to stop needing gunicorn.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(CARACAL_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		barbican==18.0.0 \
		python-keystoneclient \
		gunicorn \
		PyKMIP \
		PyMySQL \
		\"oslo.messaging[kafka]\""
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# python-barbicanclient stays in the *antelope* venv -- TEMPORARY, see below
#
# It is the only part of barbican that does not follow the service into the caracal venv,
# because it is the one part the openstack cli loads rather than the one barbican runs.
# python-barbicanclient contributes an [openstack.cli.extension] entry point plus sixteen
# [openstack.key_manager.v1] commands (secret store/get/list/delete/update, the container
# and consumer families, and the order family), and a stevedore entry point is only visible
# to the interpreter it was installed under. /usr/bin/openstack is the antelope venv's
# (core/heavyfs/Makefile links it there), so installing the client into the caracal venv
# would take `openstack secret ...` off the node entirely.
#
# This is the first caracal hop to hit that. keystone, glance, cinder and nova escaped it
# because `openstack image|volume|server ...` are osc built-ins -- python-keystoneclient and
# python-cinderclient contribute no [openstack.cli.extension] at all -- so their clients
# could move with the service. The same split is already spelled out for designate in
# core/designate/designate.mk, from the era when the cli was the system python's.
#
# TEMPORARY: this goes away when the cli itself reaches the caracal venv, at which point
# this install block moves back into the one above.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-barbicanclient"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/barbican-db-manage /usr/bin/barbican-db-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/barbican-manage /usr/bin/barbican-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/barbican-retry /usr/bin/barbican-retry
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/barbican-status /usr/bin/barbican-status
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/pkcs11-kek-rewrap /usr/bin/pkcs11-kek-rewrap
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/pkcs11-key-generation /usr/bin/pkcs11-key-generation
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/barbican-wsgi-api /usr/bin/barbican-wsgi-api
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/barbican-worker /usr/bin/barbican-worker
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/barbican-keystone-listener /usr/bin/barbican-keystone-listener

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/barbican
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/barbican

# generate default configurations
rootfs_install::
	$(Q)cp -f $(COREDIR)/barbican/barbican.conf.sample $(ROOTDIR)/tmp/barbican/
	$(Q)# copy statutory configuration templates from core directory
	$(Q)cp -f $(COREDIR)/barbican/barbican-api-paste.ini $(ROOTDIR)/tmp/barbican/
	$(Q)cp -f $(COREDIR)/barbican/api_audit_map.conf $(ROOTDIR)/tmp/barbican/
	$(Q)cp -f $(COREDIR)/barbican/barbican-functional.conf $(ROOTDIR)/tmp/barbican/
	$(Q)cp -f $(COREDIR)/barbican/gunicorn-config.py $(ROOTDIR)/tmp/barbican/
	$(Q)cp -f $(COREDIR)/barbican/vassals-barbican-api.ini $(ROOTDIR)/tmp/barbican/barbican-api.ini
	$(Q)# copy systemd unit file templates
	$(Q)cp -f $(COREDIR)/barbican/openstack-barbican-api.service $(ROOTDIR)/tmp/barbican/
	$(Q)cp -f $(COREDIR)/barbican/openstack-barbican-worker.service $(ROOTDIR)/tmp/barbican/
	$(Q)cp -f $(COREDIR)/barbican/openstack-barbican-keystone-listener.service $(ROOTDIR)/tmp/barbican/
	$(Q)cp -f $(COREDIR)/barbican/openstack-barbican-retry.service $(ROOTDIR)/tmp/barbican/

# install system directories and production files
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/barbican
	$(Q)chroot $(ROOTDIR) install -d -m 750 /var/log/barbican
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/barbican
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/barbican/vassals
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/run/barbican
	$(Q)# install configurations
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/barbican/barbican.conf.sample /etc/barbican/barbican.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/barbican/barbican-api-paste.ini /etc/barbican/barbican-api-paste.ini
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/barbican/api_audit_map.conf /etc/barbican/api_audit_map.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/barbican/barbican-functional.conf /etc/barbican/barbican-functional.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/barbican/gunicorn-config.py /etc/barbican/gunicorn-config.py
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/barbican/barbican-api.ini /etc/barbican/vassals/barbican-api.ini
	$(Q)# install systemd unit files
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/barbican/openstack-barbican-api.service /usr/lib/systemd/system/openstack-barbican-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/barbican/openstack-barbican-worker.service /usr/lib/systemd/system/openstack-barbican-worker.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/barbican/openstack-barbican-keystone-listener.service /usr/lib/systemd/system/openstack-barbican-keystone-listener.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/barbican/openstack-barbican-retry.service /usr/lib/systemd/system/openstack-barbican-retry.service

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chown root:barbican /etc/barbican
	$(Q)chroot $(ROOTDIR) chown root:barbican /etc/barbican/barbican.conf
	$(Q)chroot $(ROOTDIR) chown root:barbican /etc/barbican/barbican-api-paste.ini
	$(Q)chroot $(ROOTDIR) chown root:barbican /etc/barbican/api_audit_map.conf
	$(Q)chroot $(ROOTDIR) chown root:barbican /etc/barbican/barbican-functional.conf
	$(Q)chroot $(ROOTDIR) chown barbican:barbican /var/log/barbican
	$(Q)chroot $(ROOTDIR) chown barbican:barbican /var/run/barbican
	$(Q)chroot $(ROOTDIR) chown barbican:barbican /var/lib/barbican

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/barbican

# install custom files
rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/barbican/barbican-wsgi.conf.in ./etc/httpd/conf.d/
	$(Q)cp -f $(BARBICAN_CONFDIR)/barbican.conf $(BARBICAN_CONFDIR)/barbican.conf.def
