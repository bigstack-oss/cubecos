# Cube SDK
# cinder installation

ROOTFS_DNF += qemu-img cryptsetup lvm2 iscsi-initiator-utils device-mapper-multipath sudo sshpass
ROOTFS_DNF_NOARCH += nvmetcli targetcli

CINDER_SRCDIR := $(ROOTDIR)$(NEXT_OPENSTACK_HOME_DIR)/lib/python$(NEXT_PYTHON_VER)/site-packages/cinder
CINDER_PATCHDIR := $(COREDIR)/cinder/$(NEXT_OPENSTACK_RELEASE)_patch

CINDER_CONFDIR := $(ROOTDIR)/etc/cinder

# cinder runs out of the epoxy venv, not the caracal one it shares with every other
# 2024.1 service. cinder 26.3.0 requires os-brick 6.10 and oslo.policy 4.5 -- the
# caracal venv holds 6.7.3 and 4.3.0 -- and resolves oslo.versionedobjects 3.6,
# oslo.rootwrap 7.5, oslo.vmware 4.6 and tooz 6.3; installing that beside
# nova/neutron/manila would have upgraded the whole caracal dependency set under them,
# so the block storage service moves alone into /opt/openstack-epoxy -- the same shape
# as its caracal hop (#629), one release on, with keystone (#657) and glance (#656) as
# the venv's other occupants. Resolved against os-epoxy-pip-upper-constraints.txt the
# two sets are disjoint -- cinder adds 34 packages there and changes no version
# keystone or glance already holds.
#
# 26.3.0 is the newest 2025.1 release, the same choice #629 made with 24.5.0 for
# 2024.1. There is no schema change to go with it: Dalmatian and Epoxy add no alembic
# revision, so the db sync migrate_cinder_db runs applies nothing and the head stays
# 9c74c1c6971f.
#
# The /usr/bin/cinder-* symlinks are the only thing outside this venv that has to
# follow: the four service units, config_cinder.cpp and hex_sdk all reach cinder
# through them. The cinder-3 link is gone -- it was an RDO console script name that no
# pip-installed python-cinderclient has ever provided, so it has been dangling since
# the yoga-to-antelope hop moved this component off the rpm.
#
# Three packages have to be named because cinder's requirements ask for none of them
# and pip will not pull them in transitively:
# PyMySQL: config_cinder.cpp writes a mysql+pymysql:// connection
# oslo.messaging[kafka]: config_cinder.cpp points the notification transport at
#   kafka://
# python-memcached: config_cinder.cpp writes [keystone_authtoken] memcached_servers,
#   which makes keystonemiddleware import memcache on its first token validation
# keystone.mk and glance.mk happen to install all three into this venv too, but a
# dependency nothing asks for is one that disappears silently -- in the caracal venv
# cinder only ever had them because other components named them.
#
# py-pure-client: support Pure Storage. The driver moved from the purestorage SDK
#   (Purity//FA REST 1.x) to py-pure-client (REST 2.x) in 2024.2, and 26.3.0's
#   pure.py imports pypureclient only, so the purestorage this used to install could no
#   longer load the driver.
# pywbem: support Fujitsu Eternus DX
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(NEXT_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			cinder==26.3.0 \
			python-cinderclient \
			python-keystoneclient \
			uwsgi \
			etcd3gw \
			websocket-client \
			py-pure-client \
			pywbem \
			PyMySQL \
			\"oslo.messaging[kafka]\" \
			python-memcached"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cinder /usr/bin/cinder
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cinder-api /usr/bin/cinder-api
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cinder-backup /usr/bin/cinder-backup
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cinder-manage /usr/bin/cinder-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cinder-rootwrap /usr/bin/cinder-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cinder-rtstool /usr/bin/cinder-rtstool
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cinder-scheduler /usr/bin/cinder-scheduler
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cinder-status /usr/bin/cinder-status
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cinder-volume /usr/bin/cinder-volume
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cinder-volume-usage-audit /usr/bin/cinder-volume-usage-audit
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/cinder-wsgi /usr/bin/cinder-wsgi

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/cinder
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/cinder

# generate default configurations using oslo-config-generator
rootfs_install::
	$(Q)cp -f $(COREDIR)/cinder/cinder-dist.conf $(ROOTDIR)/tmp/cinder/
	$(Q)cp -f $(COREDIR)/cinder/cinder-config-generator.conf $(ROOTDIR)/tmp/cinder/
	$(Q)cp -f $(COREDIR)/cinder/cinder.conf.sample $(ROOTDIR)/tmp/cinder/
	$(Q)# copy statutory configuration templates from core directory
	$(Q)cp -f $(COREDIR)/cinder/cinder-sudoers $(ROOTDIR)/tmp/cinder/
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
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/cinder/cinder-dist.conf /usr/share/cinder/cinder-dist.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/cinder/cinder.conf.sample /etc/cinder/cinder.conf
	$(Q)# api-paste.ini, rootwrap.conf, resource_filters.json and the volume rootwrap
	$(Q)# filters are upstream data the cinder wheel already puts under the venv prefix
	$(Q)# through its setup.cfg data_files. They used to be checked into core/cinder
	$(Q)# verbatim, which meant they only ever moved when someone remembered to re-copy
	$(Q)# them.
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 $(NEXT_OPENSTACK_HOME_DIR)/etc/cinder/api-paste.ini /etc/cinder/api-paste.ini
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 $(NEXT_OPENSTACK_HOME_DIR)/etc/cinder/rootwrap.conf /etc/cinder/rootwrap.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 $(NEXT_OPENSTACK_HOME_DIR)/etc/cinder/resource_filters.json /etc/cinder/resource_filters.json
	$(Q)# install security configurations
	$(Q)chroot $(ROOTDIR) install -p -D -m 440 /tmp/cinder/cinder-sudoers /etc/sudoers.d/cinder
	$(Q)# install systemd unit files
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/cinder/openstack-cinder-api.service /usr/lib/systemd/system/openstack-cinder-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/cinder/openstack-cinder-scheduler.service /usr/lib/systemd/system/openstack-cinder-scheduler.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/cinder/openstack-cinder-volume.service /usr/lib/systemd/system/openstack-cinder-volume.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/cinder/openstack-cinder-backup.service /usr/lib/systemd/system/openstack-cinder-backup.service
	$(Q)# install rootwrap filters into system cinder deployment configuration
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 $(NEXT_OPENSTACK_HOME_DIR)/etc/cinder/rootwrap.d/volume.filters /etc/cinder/rootwrap.d/

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chown root:cinder /usr/share/cinder/cinder-dist.conf
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
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/cinder/builtin_models/rbd-RBDDriver.yaml ./usr/share/cube/cos/cinder/builtin_models
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/cinder
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/cinder/models
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/cinder/storage_extra_configs_ownership
