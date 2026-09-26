# Cube SDK
# barbican installation

BARBICAN_CONFDIR := $(ROOTDIR)/etc/barbican

# barbican runs out of the epoxy venv, not the caracal one it shares with every other
# 2024.1 service. 20.0.0 is the 2025.1 release, and the only one: stable/2025.1 has
# gained a pyproject.toml, wsgi module paths and a doc note since, but no second tag.
# It cannot be bumped in place: 20.0.0 requires oslo.policy>=4.5.0, which
# os-caracal-pip-upper-constraints.txt holds at 4.3.0 for octavia, heat, manila and the
# other 2024.1 services still in the caracal venv. So the service moves alone into
# $(NEXT_OPENSTACK_HOME_DIR), the same shape as its caracal hop (#632), one release on,
# after keystone, glance, cinder, nova/placement and neutron.
#
# PyKMIP: the kmip_secret_store plugin imports it unconditionally, oslo-config-generator
#   fails without it even when the plugin is unused. Still true in 20.0.0, which now
#   declares it as the [kmip] extra rather than a requirement.
# PyMySQL: config_barbican.cpp writes a mysql+pymysql:// connection URI
# oslo.messaging[kafka]: config_barbican.cpp points the notification transport at kafka
# python-memcached: config_barbican.cpp writes [keystone_authtoken] memcached_servers,
#   which makes keystonemiddleware import memcache on its first token validation
# python-keystoneclient / gunicorn: named for the same reason the ones above are -- a
#   dependency nothing asks for is one that disappears silently. keystone.mk happens to
#   install all but PyKMIP into this venv too.
#
# The /usr/bin/barbican-* links follow the service: the units, config_barbican.cpp and
# hex_sdk all reach barbican through them.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(NEXT_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		barbican==20.0.0 \
		python-keystoneclient \
		gunicorn \
		PyKMIP \
		PyMySQL \
		\"oslo.messaging[kafka]\" \
		python-memcached"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/barbican-db-manage /usr/bin/barbican-db-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/barbican-manage /usr/bin/barbican-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/barbican-retry /usr/bin/barbican-retry
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/barbican-status /usr/bin/barbican-status
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/pkcs11-kek-rewrap /usr/bin/pkcs11-kek-rewrap
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/pkcs11-key-generation /usr/bin/pkcs11-key-generation
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/barbican-wsgi-api /usr/bin/barbican-wsgi-api
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/barbican-worker /usr/bin/barbican-worker
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/barbican-keystone-listener /usr/bin/barbican-keystone-listener

# python-barbicanclient
#
# It is kept in a block of its own because it is the one part of barbican that cannot
# follow the service into the epoxy venv: it is what the openstack cli loads rather than
# what barbican runs. python-barbicanclient contributes an [openstack.cli.extension] entry
# point plus sixteen [openstack.key_manager.v1] commands (secret store/get/list/delete/
# update, the container and consumer families, and the order family), and a stevedore entry
# point is only visible to the interpreter it was installed under, so it has to sit next to
# /usr/bin/openstack or `openstack secret ...` leaves the node entirely.
#
# #632 was the first caracal hop to hit that, and #636 ended that split by moving the cli.
# The epoxy hop opens it again: /usr/bin/openstack is still the caracal venv's, so the
# client stays here until the cli moves too. keystone, glance, cinder, nova and neutron
# escaped it because `openstack identity|image|volume|server|network ...` are osc
# built-ins -- their clients contribute no [openstack.cli.extension] at all. The epoxy venv
# gets a python-barbicanclient of its own anyway, which castellan and cinder both require.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-barbicanclient"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

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
