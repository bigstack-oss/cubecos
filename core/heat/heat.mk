# Cube SDK
# heat installation

# No extra rootfs packages are needed. The RDO spec's only non-python Requires
# was shadow-utils, for the heat user and group, and
# core/heavyfs/account/centos9 already carries heat statically.
#
# openstack-heat-ui, the Horizon dashboard plugin, is deliberately no longer
# installed: Horizon imports it and Horizon still runs on the system python 3.9,
# so it cannot follow heat into the 3.10 venv. Restoring the Orchestration panel
# belongs to #609 (Upgrade Horizon from Yoga to Antelope), whose acceptance
# criteria already cover "Ensure other panels are functioning on the dashboard".

HEAT_CONFDIR := $(ROOTDIR)/etc/heat

# install heat
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			openstack-heat==20.0.1"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link the six console scripts heat declares. The venv also gains
	$(Q)# heat-db-setup and heat-keystone-setup{,-domain} (manual deployment
	$(Q)# helpers that hex_config replaces), heat-wsgi-api{,-cfn} (only used when
	$(Q)# heat is hosted under a wsgi server, which is not the layout here) and
	$(Q)# heat (the deprecated python-heatclient CLI, called nowhere in this
	$(Q)# tree); those are left unlinked on purpose.
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/heat-all /usr/bin/heat-all
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/heat-api /usr/bin/heat-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/heat-api-cfn /usr/bin/heat-api-cfn
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/heat-engine /usr/bin/heat-engine
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/heat-manage /usr/bin/heat-manage
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/heat-status /usr/bin/heat-status

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/heat
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/heat

# stage the checked-in sample config and systemd units
# NOTE: core/heat/oslo-config-generator/heat.conf is not staged. It is the input
# that produced heat.conf.sample and is kept in the repo for the next release
# hop; the image has no use for it.
rootfs_install::
	$(Q)cp -f $(COREDIR)/heat/heat.conf.sample $(ROOTDIR)/tmp/heat/
	$(Q)cp -f $(COREDIR)/heat/openstack-heat-api.service $(ROOTDIR)/tmp/heat/
	$(Q)cp -f $(COREDIR)/heat/openstack-heat-api-cfn.service $(ROOTDIR)/tmp/heat/
	$(Q)cp -f $(COREDIR)/heat/openstack-heat-engine.service $(ROOTDIR)/tmp/heat/
	$(Q)cp -f $(COREDIR)/heat/openstack-heat-all.service $(ROOTDIR)/tmp/heat/

# install system directories and files
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/heat
	$(Q)chroot $(ROOTDIR) install -d -m 755 /usr/share/heat
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/heat
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/log/heat
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/run/heat
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/heat/heat.conf.sample /etc/heat/heat.conf
	$(Q)# api-paste.ini, environment.d and templates ship inside the wheel, so
	$(Q)# pip lands them under the venv prefix; relocate them into /etc/heat the
	$(Q)# same way the RDO spec's %install does.
	$(Q)chroot $(ROOTDIR) cp -f /opt/openstack-antelope/etc/heat/api-paste.ini /etc/heat/api-paste.ini
	$(Q)chroot $(ROOTDIR) cp -rf /opt/openstack-antelope/etc/heat/environment.d /etc/heat/
	$(Q)chroot $(ROOTDIR) cp -rf /opt/openstack-antelope/etc/heat/templates /etc/heat/
	$(Q)# install systemd unit files
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/heat/openstack-heat-api.service /usr/lib/systemd/system/openstack-heat-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/heat/openstack-heat-api-cfn.service /usr/lib/systemd/system/openstack-heat-api-cfn.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/heat/openstack-heat-engine.service /usr/lib/systemd/system/openstack-heat-engine.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/heat/openstack-heat-all.service /usr/lib/systemd/system/openstack-heat-all.service

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chown root:heat /etc/heat/heat.conf
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/heat/heat.conf
	$(Q)chroot $(ROOTDIR) chown root:heat /etc/heat/api-paste.ini
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/heat/api-paste.ini
	$(Q)chroot $(ROOTDIR) chown -R root:heat /etc/heat/environment.d
	$(Q)chroot $(ROOTDIR) chown -R root:heat /etc/heat/templates
	$(Q)chroot $(ROOTDIR) chown heat:heat /var/lib/heat
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/lib/heat
	$(Q)chroot $(ROOTDIR) chown heat:heat /var/log/heat
	$(Q)chroot $(ROOTDIR) chmod 0750 /var/log/heat
	$(Q)chroot $(ROOTDIR) chown heat:heat /var/run/heat
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/run/heat

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/heat

# hex_config reads this baseline and regenerates /etc/heat/heat.conf from it, so
# it has to be taken after the install step above has replaced the file the RPMs
# used to provide.
rootfs_install::
	$(Q)cp -f $(HEAT_CONFDIR)/heat.conf $(HEAT_CONFDIR)/heat.conf.def
