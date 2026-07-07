# Cube SDK
# cinder installation

ROOTFS_DNF += qemu-img cryptsetup lvm2 iscsi-initiator-utils device-mapper-multipath sudo sshpass
ROOTFS_DNF_NOARCH += nvmetcli targetcli

CINDER_SRCDIR := $(ROOTDIR)/opt/openstack-antelope/lib/python3.10/site-packages/cinder
CINDER_PATCHDIR := $(COREDIR)/cinder/$(NEXT_OPENSTACK_RELEASE)_patch

CINDER_CONFDIR := $(ROOTDIR)/etc/cinder

# install cinder inside the python 3.10 virtual environment
# purestorage: support Pure Storage
# pywbem: support Fujitsu Eternus DX
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			cinder==22.3.0 \
			python-cinderclient \
			python-keystoneclient \
			uwsgi \
			etcd3gw \
			websocket-client \
			purestorage \
			pywbem"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder /usr/bin/cinder
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-3 /usr/bin/cinder-3
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-api /usr/bin/cinder-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-backup /usr/bin/cinder-backup
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-manage /usr/bin/cinder-manage
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-rootwrap /usr/bin/cinder-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-rtstool /usr/bin/cinder-rtstool
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-scheduler /usr/bin/cinder-scheduler
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-status /usr/bin/cinder-status
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-volume /usr/bin/cinder-volume
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-volume-usage-audit /usr/bin/cinder-volume-usage-audit
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-wsgi /usr/bin/cinder-wsgi

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/cinder
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/cinder

# generate default configurations using oslo-config-generator
rootfs_install::
	$(Q)cp -f $(COREDIR)/cinder/cinder-config-generator.conf $(ROOTDIR)/tmp/cinder/
	$(Q)cp -f $(COREDIR)/cinder/cinder.conf.sample $(ROOTDIR)/tmp/cinder/
	$(Q)# copy statutory configuration templates from core directory
	$(Q)cp -f $(COREDIR)/cinder/api-paste.ini $(ROOTDIR)/tmp/cinder/
	$(Q)cp -f $(COREDIR)/cinder/rootwrap.conf $(ROOTDIR)/tmp/cinder/
	$(Q)cp -f $(COREDIR)/cinder/resource_filters.json $(ROOTDIR)/tmp/cinder/
	$(Q)cp -f $(COREDIR)/cinder/cinder-sudoers $(ROOTDIR)/tmp/cinder/
	$(Q)cp -f $(COREDIR)/cinder/volume.filters $(ROOTDIR)/tmp/cinder/
	$(Q)# copy systemd unit file templates
	$(Q)cp -f $(COREDIR)/cinder/openstack-cinder-api.service $(ROOTDIR)/tmp/cinder/
	$(Q)cp -f $(COREDIR)/cinder/openstack-cinder-scheduler.service $(ROOTDIR)/tmp/cinder/
	$(Q)cp -f $(COREDIR)/cinder/openstack-cinder-volume.service $(ROOTDIR)/tmp/cinder/
	$(Q)cp -f $(COREDIR)/cinder/openstack-cinder-backup.service $(ROOTDIR)/tmp/cinder/

# install system directories and production files
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/cinder
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/cinder/tmp
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/log/cinder
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/cinder
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/cinder/volumes
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/cinder/rootwrap.d
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/run/cinder
	$(Q)# install configurations
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/cinder/cinder.conf.sample /etc/cinder/cinder.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/cinder/api-paste.ini /etc/cinder/api-paste.ini
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/cinder/rootwrap.conf /etc/cinder/rootwrap.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/cinder/resource_filters.json /etc/cinder/resource_filters.json
	$(Q)# install security configurations
	$(Q)chroot $(ROOTDIR) install -p -D -m 440 /tmp/cinder/cinder-sudoers /etc/sudoers.d/cinder
	$(Q)# install systemd unit files
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/cinder/openstack-cinder-api.service /usr/lib/systemd/system/openstack-cinder-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/cinder/openstack-cinder-scheduler.service /usr/lib/systemd/system/openstack-cinder-scheduler.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/cinder/openstack-cinder-volume.service /usr/lib/systemd/system/openstack-cinder-volume.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/cinder/openstack-cinder-backup.service /usr/lib/systemd/system/openstack-cinder-backup.service
	$(Q)# install rootwrap filters into system cinder deployment configuration
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/cinder/volume.filters /etc/cinder/rootwrap.d/

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chown root:cinder /etc/cinder/cinder.conf
	$(Q)chroot $(ROOTDIR) chown root:cinder /etc/cinder/api-paste.ini
	$(Q)chroot $(ROOTDIR) chown root:cinder /etc/cinder/rootwrap.conf
	$(Q)chroot $(ROOTDIR) chown root:cinder /etc/cinder/resource_filters.json
	$(Q)chroot $(ROOTDIR) chown cinder:root /var/log/cinder
	$(Q)chroot $(ROOTDIR) chmod 0750 /var/log/cinder
	$(Q)chroot $(ROOTDIR) chown cinder:root /var/run/cinder
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/run/cinder
	$(Q)chroot $(ROOTDIR) chown cinder:root /etc/cinder/volumes
	$(Q)chroot $(ROOTDIR) chmod 0755 /etc/cinder/volumes
	$(Q)chroot $(ROOTDIR) chown -R cinder:cinder /var/lib/cinder
	$(Q)chroot $(ROOTDIR) chown -R cinder:cinder /var/lib/cinder/tmp

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/cinder

# install custom files
rootfs_install::
	$(Q)[ -d $(CINDER_PATCHDIR) ] && cp -rf $(CINDER_PATCHDIR)/* $(CINDER_SRCDIR)/ || /bin/true

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p /var/lock/os_brick
	$(Q)# give full read-write-execute permissions to both service users
	$(Q)chroot $(ROOTDIR) setfacl -m u:cinder:rwx /var/lock/os_brick
	$(Q)chroot $(ROOTDIR) setfacl -m u:glance:rwx /var/lock/os_brick
	$(Q)# ensure any future lock files created inside automatically inherit these permissions
	$(Q)chroot $(ROOTDIR) setfacl -d -m u:cinder:rwx /var/lock/os_brick
	$(Q)chroot $(ROOTDIR) setfacl -d -m u:glance:rwx /var/lock/os_brick
	$(Q)cp -f $(CINDER_CONFDIR)/cinder.conf $(CINDER_CONFDIR)/cinder.conf.org
	$(Q)touch $(CINDER_CONFDIR)/cinder.conf.def
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cinder/cinder.d
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cinder/external_storage_extra_configs
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/openstack-cinder-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/openstack-cinder-scheduler.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/openstack-cinder-volume.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/openstack-cinder-backup.service ./lib/systemd/system
#	$(Q)cp -f $(COREDIR)/cinder/db_schema_stein.tgz $(CINDER_CONFDIR)
	$(Q)chroot $(ROOTDIR) systemctl disable iscsi
	$(Q)chroot $(ROOTDIR) mkdir -p /usr/share/cube/cos/cinder
	$(Q)chroot $(ROOTDIR) mkdir -p /usr/share/cube/cos/cinder/builtin_models
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/builtin_models/dell_emc-sc-storagecenter_fc-SCFCDriver.yaml ./usr/share/cube/cos/cinder/builtin_models
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/builtin_models/dell_emc-powerstore-driver-PowerStoreDriver.yaml ./usr/share/cube/cos/cinder/builtin_models
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/builtin_models/nfs-NfsDriver.yaml ./usr/share/cube/cos/cinder/builtin_models
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/builtin_models/fujitsu-eternus_dx-eternus_dx_fc-FJDXFCDriver.yaml ./usr/share/cube/cos/cinder/builtin_models
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/builtin_models/fujitsu-eternus_dx-eternus_dx_iscsi-FJDXISCSIDriver.yaml ./usr/share/cube/cos/cinder/builtin_models
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/cinder
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/cinder/models
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/cinder/storage_extra_configs_ownership
