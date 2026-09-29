# Cube SDK
# ironic installation

IRONIC_CONF_DIR := /etc/ironic
IRONIC_INSP_CONF_DIR := /etc/ironic-inspector

# https://releases.openstack.org/epoxy/index.html#epoxy-ironic -- 29.1.0 is the newest
# 2025.1 release. ironic is cycle-with-intermediary: 27.0.0 and 28.0.0 were the cycle's
# intermediary releases on bugfix branches, and stable/2025.1 starts at 29.0.0. 29.1.0
# is 29.0.6 plus the socat serial console fix, which CubeCOS does not use. The
# stable releases since 29.0.0 carry the branch's security fixes: kernel_append_params
# sanitising (CVE-2026-46447), the pxe_template override, the IPMI send_raw step, the
# anaconda ISO path check (CVE-2026-48681) and the bootloader-install switch
# (CVE-2026-43003).
IRONIC_VER := 29.1.0

# https://releases.openstack.org/epoxy/index.html#epoxy-ironic-inspector -- 12.4.0 is the
# only 2025.1 release, and the project is in maintenance mode: upstream says to move
# to ironic's built-in in-band inspection and to expect no further releases.
#
# It is still kept rather than replaced by that built-in inspection ("enabled_inspect
# interfaces = agent", the ironic.inspection.hooks entry points and the
# ironic-pxe-filter service), because the migration is the adoption of a new feature
# and this issue's "ignore the new features introduced in the new version" criterion
# says not to adopt it here. config_ironic.cpp pins enabled_inspect_interfaces to
# "inspector" and rewrites it on every Commit(), so the built-in path stays
# unreachable -- which is also what keeps the migrate_to_builtin_inspection online
# data migration a no-op: it returns (0, 0) while "inspector" is still in that list.
IRONIC_INSP_VER := 12.4.0

# ironic-ui follows horizon, not the ironic service: it installs next to horizon
# because that is where collectstatic collects panels from. #662 moved horizon into
# the epoxy venv, so this moved with it. 6.5.0 is the epoxy release, and the only one
# of the series -- https://releases.openstack.org/epoxy/index.html#epoxy-ironic-ui. It
# reaches the api over HTTP through python-ironicclient and imports nothing from
# ironic, which is why it could stay a release behind the service while horizon did.
# Horizon plugins are not in the epoxy upper-constraints either (that file only covers
# libraries), so the pin is explicit.
IRONIC_UI_VER := 6.5.0

# python-ironicclient owns the `baremetal` osc plugin, and an entry point is only
# visible to the interpreter it was installed under, so it has to sit next to whichever
# interpreter runs /usr/bin/openstack. #636 made that the caracal venv and #662 the
# epoxy one. It used to be present in the caracal venv without a pip line of its own,
# because ironic-ui (installed below) and python-watcher (core/watcher) both declared
# it and both were in that venv -- two declarers was what made leaving it implicit
# safe where heat and manila had to be explicit. #670 took python-watcher to the epoxy
# venv and left ironic-ui as the only one, which is the failure mode designate.mk
# records for a single transitive declarer: the client would leave with the panel,
# whatever the cli needs. So the web ui block below names it, and it followed the cli
# to epoxy in that block. The epoxy venv holds it as an openstack-heat, python-watcher
# and ironic-ui requirement too; the line is named for the cli regardless, and nova's
# ironic driver talks to the API through openstacksdk, not through this client.
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

# install ironic and ironic-inspector into the epoxy venv
#
# ironic runs out of the epoxy venv, not the caracal one it shared with the 2024.1
# services still there. It could not be bumped in place: 29.x and 12.4.0 both
# require oslo.policy>=4.5.0, which os-caracal-pip-upper-constraints.txt held at 4.3.0
# for octavia, manila and the other 2024.1 services. So the pair moved alone into
# $(OPENSTACK_HOME_DIR), the same shape as its caracal hop (#637), one release on,
# after keystone, glance, cinder, nova/placement, neutron, barbican, cyborg, designate
# and heat.
#
# Four packages have to be named because neither service's requirements.txt asks for
# them and pip will not pull them in transitively:
# PyMySQL: config_ironic.cpp writes a mysql+pymysql:// connection for both services
# oslo.messaging[kafka]: config_ironic.cpp points both notification transports at
#   kafka://
# python-memcached: config_ironic.cpp writes [keystone_authtoken] memcached_servers
#   for both, which makes keystonemiddleware import memcache on its first token
#   validation
# tooz[memcached]: config_ironic.cpp writes the inspector's [coordination]
#   backend_url as memcached://, and tooz's memcached driver imports pymemcache. The
#   caracal venv only ever had it because horizon.mk installs it for django's cache,
#   and nothing in this venv does. Without it the inspector does not fail: in
#   standalone mode it logs "Coordination backend cannot be started, assuming no
#   other instances are running" and carries on, so on a multi-control cluster each
#   node's inspector would run as if it were the only one.
# The first three happen to be in this venv already, but a dependency nothing asks
# for is one that disappears silently.
#
# NOTE: networking-baremetal (the 'baremetal' ML2 driver plus the
# ironic-neutron-agent binary) is pip installed by core/neutron/neutron.mk,
# because config_neutron.cpp always sets ml2.mechanism_drivers=ovn,baremetal.
# Do not install it a second time here — only link the binary ironic owns.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		ironic==$(IRONIC_VER) \
		ironic-inspector==$(IRONIC_INSP_VER) \
		PyMySQL \
		\"oslo.messaging[kafka]\" \
		python-memcached \
		\"tooz[memcached]\""
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries. Two console scripts are deliberately left unlinked, both new
	$(Q)# features: ironic-pxe-filter (2024.1), the built-in dnsmasq PXE filter that
	$(Q)# goes with the "agent" inspect interface -- we stay on ironic-inspector for
	$(Q)# introspection (see IRONIC_INSP_VER), so nothing would start it -- and
	$(Q)# ironic-novncproxy (2025.1), the graphical console proxy, which needs a [vnc]
	$(Q)# section config_ironic.cpp does not write. The share/ironic/vnc-container
	$(Q)# data_files that goes with it stays under the venv prefix, unused.
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic /usr/bin/ironic
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic-api /usr/bin/ironic-api
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic-api-wsgi /usr/bin/ironic-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic-conductor /usr/bin/ironic-conductor
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic-dbsync /usr/bin/ironic-dbsync
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic-rootwrap /usr/bin/ironic-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic-status /usr/bin/ironic-status
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic-inspector /usr/bin/ironic-inspector
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic-inspector-api-wsgi /usr/bin/ironic-inspector-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic-inspector-conductor /usr/bin/ironic-inspector-conductor
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic-inspector-dbsync /usr/bin/ironic-inspector-dbsync
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic-inspector-migrate-data /usr/bin/ironic-inspector-migrate-data
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic-inspector-rootwrap /usr/bin/ironic-inspector-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic-inspector-status /usr/bin/ironic-inspector-status
	$(Q)# provided by networking-baremetal, installed with neutron -- so it follows
	$(Q)# neutron's venv, not ironic's. neutron moved to the epoxy one first (#654)
	$(Q)# and reopened the split #1194 had to reason about; with ironic in the epoxy
	$(Q)# venv too, the agent and the service it reports for share an interpreter
	$(Q)# again, as they did after #637.
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ironic-neutron-agent /usr/bin/ironic-neutron-agent

# install the osc plugin and the ironic web ui plugin
#
# python-ironicclient is named for the cli -- see the note at the top. No version is
# named: os-epoxy-pip-upper-constraints.txt already carries it, so a version here
# could only drift from that file. Nothing is linked: the cli reaches it through
# /usr/bin/openstack, not through its own baremetal script.
#
# openstack-ironic-ui was dropped when ironic moved to pip, because horizon was still
# on python 3.9 and could not import a package from the venv (#609 deferred it).
# horizon is in the venv now, so the Bare Metal Provisioning panel comes back.
# Registering the panel is core/horizon's job, where every dashboard action lives.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-ironicclient
	$(Q)# --no-build-isolation: ironic-ui pulls horizon, whose sdist-only XStatic
	$(Q)# dependencies cannot be built against a current setuptools. See the note by
	$(Q)# the venv bootstrap in core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
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
	$(Q)# venv prefix and it is relocated from there rather than checked in, which
	$(Q)# is how 24.1.5's "DEPRECATED for removal: Ironic no longer needs root."
	$(Q)# notice arrived without a repo edit. 29.1.0's copy is byte-identical.
	$(Q)# ironic-inspector carries no data_files at all, so its two rootwrap files
	$(Q)# stay checked in.
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 $(OPENSTACK_HOME_DIR)/etc/ironic/rootwrap.conf $(IRONIC_CONF_DIR)/rootwrap.conf
	$(Q)# rootwrap.d/ironic-utils.filters is the other data_file, and it is
	$(Q)# deliberately NOT installed. 24.1.5 emptied it -- ironic's last two
	$(Q)# run_as_root=True call sites (mount/umount in ironic/common/utils.py) are
	$(Q)# gone, so all that is left is three comment lines and no [Filters] section,
	$(Q)# and 29.1.0 ships the same file. oslo_rootwrap.wrapper.load_filters() calls
	$(Q)# filterconfig.items("Filters") for every file under filters_path, so one
	$(Q)# sectionless file raises NoSectionError and takes down the *whole* filter
	$(Q)# set -- installing it made ironic-rootwrap refuse every command on 24.1.5.
	$(Q)#
	$(Q)# rootwrap.d/ironic-lib.filters, which #1194 relocated from the prefix for
	$(Q)# ironic-lib's disk utilities, is gone with ironic-lib: 2025.1 retired the
	$(Q)# library, and neither ironic 29.1.0 nor ironic-inspector 12.4.0 requires it,
	$(Q)# so nothing installs the file any more. Nothing needs it either: ironic
	$(Q)# 29.1.0 has no run_as_root=True call site left, and
	$(Q)# ironic.common.utils.execute() now drops the flag with a DeprecationWarning.
	$(Q)# So rootwrap.d stays empty, and ironic-rootwrap authorises nothing.
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
