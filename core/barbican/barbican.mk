# Cube SDK
# barbican installation

BARBICAN_CONFDIR := $(ROOTDIR)/etc/barbican

# install barbican inside the python 3.10 virtual environment
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		barbican==16.0.2 \
		python-barbicanclient \
		python-keystoneclient \
		gunicorn \
		PyKMIP"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/barbican-db-manage /usr/bin/barbican-db-manage
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/barbican-manage /usr/bin/barbican-manage
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/barbican-retry /usr/bin/barbican-retry
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/barbican-status /usr/bin/barbican-status
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/pkcs11-kek-rewrap /usr/bin/pkcs11-kek-rewrap
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/pkcs11-key-generation /usr/bin/pkcs11-key-generation
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/barbican-wsgi-api /usr/bin/barbican-wsgi-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/barbican-worker /usr/bin/barbican-worker
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/barbican-keystone-listener /usr/bin/barbican-keystone-listener

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
