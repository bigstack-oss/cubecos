# Cube SDK
# ironic installation

IRONIC_CONF_DIR := /etc/ironic
IRONIC_INSP_CONF_DIR := /etc/ironic-inspector

# System requirements formerly pulled in by the openstack-ironic RPMs.
# ipmitool backs enabled_hardware_types=ipmi / enabled_management_interfaces=ipmitool
# (RDO only listed it as a weak dependency, so pip gives us nothing here);
# qemu-img, mtools, dosfstools and xorriso are what the conductor shells out to
# for image conversion and config-drive creation. They used to arrive through
# other components' RPM sets, which is not something ironic should rely on.
#
# pykickstart, the remaining Requires of RDO's openstack-ironic-conductor, is left
# out for the same reason python3-dracclient and python3-scciclient are: it is only
# reached through the anaconda deploy interface, and config_ironic.cpp pins
# enabled_deploy_interfaces to "direct" and rewrites it on every Commit(). ironic
# only names it in an error string, so both ironic.common.pxe_utils and
# ironic.drivers.modules.deploy_utils import fine without it and anyone who does
# enable anaconda gets "Please install pykickstart package to enable ...".
ROOTFS_DNF += tftp-server ipmitool qemu-img mtools dosfstools xorriso
ROOTFS_DNF_NOARCH += syslinux-tftpboot

# install ironic and ironic-inspector inside the python 3.10 virtual environment
# NOTE: networking-baremetal (the 'baremetal' ML2 driver plus the
# ironic-neutron-agent binary) is pip installed by core/neutron/neutron.mk,
# because config_neutron.cpp always sets ml2.mechanism_drivers=ovn,baremetal.
# Do not install it a second time here — only link the binary ironic owns.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		ironic==21.4.4 \
		ironic-inspector==11.4.1"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic /usr/bin/ironic
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic-api /usr/bin/ironic-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic-api-wsgi /usr/bin/ironic-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic-conductor /usr/bin/ironic-conductor
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic-dbsync /usr/bin/ironic-dbsync
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic-rootwrap /usr/bin/ironic-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic-status /usr/bin/ironic-status
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic-inspector /usr/bin/ironic-inspector
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic-inspector-api-wsgi /usr/bin/ironic-inspector-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic-inspector-conductor /usr/bin/ironic-inspector-conductor
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic-inspector-dbsync /usr/bin/ironic-inspector-dbsync
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic-inspector-migrate-data /usr/bin/ironic-inspector-migrate-data
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic-inspector-rootwrap /usr/bin/ironic-inspector-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic-inspector-status /usr/bin/ironic-inspector-status
	$(Q)# provided by networking-baremetal, installed with neutron
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/ironic-neutron-agent /usr/bin/ironic-neutron-agent

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/ironic
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/ironic

# stage configuration templates from the core directory
rootfs_install::
	$(Q)cp -f $(COREDIR)/ironic/ironic.conf.sample $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/inspector.conf.sample $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/inspector-dist.conf $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/rootwrap.conf $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/inspector-rootwrap.conf $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/ironic-utils.filters $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/ironic-inspector.filters $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/ironic-sudoers $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/ironic-inspector-sudoers $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/openstack-ironic-api.service $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/openstack-ironic-conductor.service $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/openstack-ironic-inspector.service $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/ironic-neutron-agent.service $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/openstack-ironic-file-server.service $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/openstack-ironic-inspector-dnsmasq.service $(ROOTDIR)/tmp/ironic/

# install system directories and production files
rootfs_install::
	$(Q)# install base configurations
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(IRONIC_CONF_DIR)
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(IRONIC_CONF_DIR)/rootwrap.d
	$(Q)chroot $(ROOTDIR) install -d -m 750 $(IRONIC_INSP_CONF_DIR)
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(IRONIC_INSP_CONF_DIR)/rootwrap.d
	$(Q)chroot $(ROOTDIR) cp -f /tmp/ironic/ironic.conf.sample $(IRONIC_CONF_DIR)/ironic.conf
	$(Q)chroot $(ROOTDIR) cp -f /tmp/ironic/inspector.conf.sample $(IRONIC_INSP_CONF_DIR)/inspector.conf
	$(Q)# the inspector unit passes this file to --config-file explicitly
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/ironic/inspector-dist.conf $(IRONIC_INSP_CONF_DIR)/inspector-dist.conf
	$(Q)# install rootwrap configurations
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/ironic/rootwrap.conf $(IRONIC_CONF_DIR)/rootwrap.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/ironic/ironic-utils.filters $(IRONIC_CONF_DIR)/rootwrap.d/ironic-utils.filters
	$(Q)# ironic-lib carries a second filter set as wheel data, which RDO relocates in
	$(Q)# python-ironic-lib.spec rather than in the ironic spec -- easy to lose when only
	$(Q)# the service's own spec is ported. It authorises the commands
	$(Q)# ironic_lib/disk_utils.py and ironic_lib/disk_partitioner.py run with
	$(Q)# run_as_root=True (blkid, blockdev, lsblk, qemu-img, wipefs, sgdisk, partprobe,
	$(Q)# mkfs, dd, parted, ...), so ironic-rootwrap denies all of them if it is absent.
	$(Q)# Take it from the venv prefix instead of checking it in, so it tracks whatever
	$(Q)# ironic-lib the pinned ironic resolves to.
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /opt/openstack-antelope/etc/ironic/rootwrap.d/ironic-lib.filters $(IRONIC_CONF_DIR)/rootwrap.d/ironic-lib.filters
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/ironic/inspector-rootwrap.conf $(IRONIC_INSP_CONF_DIR)/rootwrap.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/ironic/ironic-inspector.filters $(IRONIC_INSP_CONF_DIR)/rootwrap.d/ironic-inspector.filters
	$(Q)# install security configurations
	$(Q)chroot $(ROOTDIR) install -p -D -m 440 /tmp/ironic/ironic-sudoers /etc/sudoers.d/ironic
	$(Q)chroot $(ROOTDIR) install -p -D -m 440 /tmp/ironic/ironic-inspector-sudoers /etc/sudoers.d/ironic-inspector
	$(Q)# install systemd unit files
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/ironic/openstack-ironic-api.service /usr/lib/systemd/system/openstack-ironic-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/ironic/openstack-ironic-conductor.service /usr/lib/systemd/system/openstack-ironic-conductor.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/ironic/openstack-ironic-inspector.service /usr/lib/systemd/system/openstack-ironic-inspector.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/ironic/ironic-neutron-agent.service /usr/lib/systemd/system/ironic-neutron-agent.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/ironic/openstack-ironic-file-server.service /usr/lib/systemd/system/openstack-ironic-file-server.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/ironic/openstack-ironic-inspector-dnsmasq.service /usr/lib/systemd/system/openstack-ironic-inspector-dnsmasq.service
	$(Q)# setup directories
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/ironic
	$(Q)chroot $(ROOTDIR) install -d -m 750 /var/log/ironic
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/ironic-inspector
	$(Q)# consumed by the dnsmasq pxe filter; created to stay on par with the RPM layout
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/ironic-inspector/dhcp-hostsdir
	$(Q)chroot $(ROOTDIR) install -d -m 750 /var/log/ironic-inspector
	$(Q)chroot $(ROOTDIR) install -d -m 750 /var/log/ironic-inspector/ramdisk
	$(Q)# tftp/pxe server root
	$(Q)chroot $(ROOTDIR) install -d -m 755 /tftpboot/pxelinux.cfg
	$(Q)chroot $(ROOTDIR) install -d -m 755 /tftpboot/images

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chown root:ironic $(IRONIC_CONF_DIR)
	$(Q)chroot $(ROOTDIR) chown root:ironic $(IRONIC_CONF_DIR)/ironic.conf
	$(Q)chroot $(ROOTDIR) chmod 0640 $(IRONIC_CONF_DIR)/ironic.conf
	$(Q)chroot $(ROOTDIR) chown root:ironic $(IRONIC_CONF_DIR)/rootwrap.conf
	$(Q)chroot $(ROOTDIR) chown root:root $(IRONIC_CONF_DIR)/rootwrap.d/ironic-utils.filters
	$(Q)chroot $(ROOTDIR) chown root:root $(IRONIC_CONF_DIR)/rootwrap.d/ironic-lib.filters
	$(Q)chroot $(ROOTDIR) chown root:ironic-inspector $(IRONIC_INSP_CONF_DIR)
	$(Q)chroot $(ROOTDIR) chown root:ironic-inspector $(IRONIC_INSP_CONF_DIR)/inspector.conf
	$(Q)chroot $(ROOTDIR) chmod 0640 $(IRONIC_INSP_CONF_DIR)/inspector.conf
	$(Q)chroot $(ROOTDIR) chown root:ironic-inspector $(IRONIC_INSP_CONF_DIR)/inspector-dist.conf
	$(Q)chroot $(ROOTDIR) chown root:ironic-inspector $(IRONIC_INSP_CONF_DIR)/rootwrap.conf
	$(Q)chroot $(ROOTDIR) chown root:root $(IRONIC_INSP_CONF_DIR)/rootwrap.d/ironic-inspector.filters
	$(Q)chroot $(ROOTDIR) chown ironic:ironic /var/lib/ironic
	$(Q)chroot $(ROOTDIR) chown ironic:ironic /var/log/ironic
	$(Q)chroot $(ROOTDIR) chown ironic-inspector:ironic-inspector /var/lib/ironic-inspector
	$(Q)chroot $(ROOTDIR) chown ironic-inspector:ironic-inspector /var/lib/ironic-inspector/dhcp-hostsdir
	$(Q)chroot $(ROOTDIR) chown ironic-inspector:ironic-inspector /var/log/ironic-inspector
	$(Q)chroot $(ROOTDIR) chown ironic-inspector:ironic-inspector /var/log/ironic-inspector/ramdisk
	$(Q)chroot $(ROOTDIR) chown -R ironic /tftpboot

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/ironic

# install custom files
rootfs_install::
	$(Q)cp -f $(ROOTDIR)/$(IRONIC_CONF_DIR)/ironic.conf $(ROOTDIR)/$(IRONIC_CONF_DIR)/ironic.conf.def
	$(Q)cp -f $(ROOTDIR)/$(IRONIC_INSP_CONF_DIR)/inspector.conf $(ROOTDIR)/$(IRONIC_INSP_CONF_DIR)/inspector.conf.def

rootfs_install::
	$(Q)for ns in $$(find $(ROOTDIR)/usr/lib/systemd/system/*ironic*.service) ; do sed -i /^Timeout*/d $$ns ; done
