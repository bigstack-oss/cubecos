# Cube SDK
# ironic installation

IRONIC_CONF_DIR := /etc/ironic
IRONIC_INSP_CONF_DIR := /etc/ironic-inspector

# https://releases.openstack.org/caracal/index.html#caracal-ironic -- last numeric
# 2024.1 revision. The caracal cycle for ironic runs 23.1.0 -> 24.1.5; 24.1.5 is the
# same "last numeric revision of the series" rule #1194 used to land on 21.4.4.
IRONIC_VER := 24.1.5

# https://releases.openstack.org/caracal/index.html#caracal-ironic-inspector -- the
# 2024.1 cycle runs 11.8.0 -> 12.1.1, so 12.1.1 is its last numeric revision.
#
# ironic-inspector is kept rather than replaced by the in-band inspection ironic
# 24.1.5 grows of its own ("enabled_inspect_interfaces = agent", the new
# ironic.inspection.hooks entry points and the ironic-pxe-filter service). That is a
# new feature of the release, and this issue's "ignore the new features introduced in
# the new version" criterion says not to adopt it here. config_ironic.cpp pins
# enabled_inspect_interfaces to "inspector" and rewrites it on every Commit(), so the
# built-in path stays unreachable -- which is also what makes 24.1.5's new
# migrate_to_builtin_inspection online data migration a no-op: it returns (0, 0)
# while "inspector" is still in that list.
IRONIC_INSP_VER := 12.1.1

# ironic-ui follows horizon, not the ironic service: it installs next to horizon
# because that is where collectstatic collects panels from. #636 moved horizon into
# the caracal venv, so this moved with it. 6.3.0 is the caracal release --
# https://releases.openstack.org/caracal/index.html#caracal-ironic-ui. It reaches the
# api over HTTP through python-ironicclient and imports nothing from ironic, so it
# never had to move when the service did. Horizon plugins are not in the caracal
# upper-constraints either (that file only covers libraries), so the pin is explicit.
IRONIC_UI_VER := 6.3.0

# python-ironicclient owns the `baremetal` osc plugin, and an entry point is only
# visible to the interpreter it was installed under, so it has to sit next to whichever
# interpreter runs /usr/bin/openstack. #636 made that the caracal venv, where it is
# already present without a pip line of its own: ironic-ui (installed below) and
# python-watcher (core/watcher) both declare it and both are in that venv, so it is
# guaranteed there rather than lucky. Two declarers is what makes it safe to leave
# implicit here where heat and manila had to be explicit -- see designate.mk for the
# failure mode a single transitive declarer produces.
#
# System requirements formerly pulled in by the openstack-ironic RPMs.
# ipmitool backs enabled_hardware_types=ipmi / enabled_management_interfaces=ipmitool
# (RDO only listed it as a weak dependency, so pip gives us nothing here);
# qemu-img, mtools, dosfstools and xorriso are what the conductor shells out to
# for image conversion and config-drive creation. They used to arrive through
# other components' RPM sets, which is not something ironic should rely on.
#
# pykickstart, the remaining Requires of RDO's openstack-ironic-conductor, is left
# out for the same reason python3-dracclient and python3-scciclient are. (Note that
# openstack-ironic-ui, dropped alongside those two, *is* back -- see the ironic-ui
# install further down.) It is only
# reached through the anaconda deploy interface, and config_ironic.cpp pins
# enabled_deploy_interfaces to "direct" and rewrites it on every Commit(). ironic
# only names it in an error string, so both ironic.common.pxe_utils and
# ironic.drivers.modules.deploy_utils import fine without it and anyone who does
# enable anaconda gets "Please install pykickstart package to enable ...".
ROOTFS_DNF += tftp-server ipmitool qemu-img mtools dosfstools xorriso
ROOTFS_DNF_NOARCH += syslinux-tftpboot

# install ironic and ironic-inspector inside the caracal python 3.11 virtual
# environment
# NOTE: networking-baremetal (the 'baremetal' ML2 driver plus the
# ironic-neutron-agent binary) is pip installed by core/neutron/neutron.mk,
# because config_neutron.cpp always sets ml2.mechanism_drivers=ovn,baremetal.
# Do not install it a second time here — only link the binary ironic owns.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(CARACAL_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		ironic==$(IRONIC_VER) \
		ironic-inspector==$(IRONIC_INSP_VER)"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries. 24.1.5 adds one console script, ironic-pxe-filter -- the
	$(Q)# built-in dnsmasq PXE filter that goes with the new "agent" inspect
	$(Q)# interface. It is deliberately left unlinked: we stay on ironic-inspector
	$(Q)# for introspection (see IRONIC_INSP_VER), so nothing would start it.
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic /usr/bin/ironic
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic-api /usr/bin/ironic-api
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic-api-wsgi /usr/bin/ironic-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic-conductor /usr/bin/ironic-conductor
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic-dbsync /usr/bin/ironic-dbsync
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic-rootwrap /usr/bin/ironic-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic-status /usr/bin/ironic-status
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic-inspector /usr/bin/ironic-inspector
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic-inspector-api-wsgi /usr/bin/ironic-inspector-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic-inspector-conductor /usr/bin/ironic-inspector-conductor
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic-inspector-dbsync /usr/bin/ironic-inspector-dbsync
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic-inspector-migrate-data /usr/bin/ironic-inspector-migrate-data
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic-inspector-rootwrap /usr/bin/ironic-inspector-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic-inspector-status /usr/bin/ironic-inspector-status
	$(Q)# provided by networking-baremetal, installed with neutron -- so it follows
	$(Q)# neutron's venv, not ironic's. Both are caracal now, so the split #1194 had
	$(Q)# to reason about is gone; the link is unchanged.
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/ironic-neutron-agent /usr/bin/ironic-neutron-agent

# install the ironic web ui plugin
#
# openstack-ironic-ui was dropped when ironic moved to pip, because horizon was still
# on python 3.9 and could not import a package from the venv (#609 deferred it).
# horizon is in the venv now, so the Bare Metal Provisioning panel comes back.
# Registering the panel is core/horizon's job, where every dashboard action lives.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)# --no-build-isolation: ironic-ui pulls horizon, whose sdist-only XStatic
	$(Q)# dependencies cannot be built against a current setuptools. See the note by
	$(Q)# the venv bootstrap in core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) $(CARACAL_OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		ironic-ui==$(IRONIC_UI_VER)
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/ironic
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/ironic

# stage configuration templates from the core directory
# NOTE: core/ironic/oslo-config-generator/ is not staged. Those two files are the
# inputs that produced ironic.conf.sample and inspector.conf.sample and are kept in
# the repo for the next release hop; the image has no use for them.
rootfs_install::
	$(Q)cp -f $(COREDIR)/ironic/ironic.conf.sample $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/inspector.conf.sample $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/inspector-dist.conf $(ROOTDIR)/tmp/ironic/
	$(Q)cp -f $(COREDIR)/ironic/inspector-rootwrap.conf $(ROOTDIR)/tmp/ironic/
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
	$(Q)# install rootwrap configurations. ironic ships rootwrap.conf as a wheel
	$(Q)# data_file ([files] data_files in its setup.cfg), so pip lands it under the
	$(Q)# venv prefix and it is relocated from there rather than checked in -- the
	$(Q)# same treatment ironic-lib.filters has had since #1194, and the reason
	$(Q)# 24.1.5's "DEPRECATED for removal: Ironic no longer needs root." notice
	$(Q)# arrives without a repo edit. ironic-inspector carries no data_files at all,
	$(Q)# so its two rootwrap files stay checked in.
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 $(CARACAL_OPENSTACK_HOME_DIR)/etc/ironic/rootwrap.conf $(IRONIC_CONF_DIR)/rootwrap.conf
	$(Q)# rootwrap.d/ironic-utils.filters is the other data_file, and it is
	$(Q)# deliberately NOT installed any more. 24.1.5 emptied it -- ironic's last two
	$(Q)# run_as_root=True call sites (mount/umount in ironic/common/utils.py) are
	$(Q)# gone, so all that is left is three comment lines and no [Filters] section.
	$(Q)# oslo_rootwrap.wrapper.load_filters() calls filterconfig.items("Filters") for
	$(Q)# every file under filters_path, so one sectionless file raises
	$(Q)# NoSectionError and takes down the *whole* filter set -- installing it would
	$(Q)# make ironic-rootwrap refuse every command ironic-lib.filters authorises.
	$(Q)# Verified A/B on the node: with the 24.1.5 file present, `ironic-rootwrap
	$(Q)# ... blkid` exits 1 with NoSectionError; without it, blkid, lsblk, sgdisk,
	$(Q)# partprobe and wipefs all pass and an unfiltered command is still refused.
	$(Q)# ironic-lib carries a second filter set as wheel data, which RDO relocates in
	$(Q)# python-ironic-lib.spec rather than in the ironic spec -- easy to lose when only
	$(Q)# the service's own spec is ported. It authorises the commands
	$(Q)# ironic_lib/disk_utils.py and ironic_lib/disk_partitioner.py run with
	$(Q)# run_as_root=True (blkid, blockdev, lsblk, qemu-img, wipefs, sgdisk, partprobe,
	$(Q)# mkfs, dd, parted, ...), so ironic-rootwrap denies all of them if it is absent.
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 $(CARACAL_OPENSTACK_HOME_DIR)/etc/ironic/rootwrap.d/ironic-lib.filters $(IRONIC_CONF_DIR)/rootwrap.d/ironic-lib.filters
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
