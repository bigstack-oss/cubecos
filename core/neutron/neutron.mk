# Cube SDK
# neutron installation

# OVN is held at 24.03.8-31.el9s on Open vSwitch 3.3.8-7.el9s -- the newest of each in
# centos-nfv-openvswitch, and the pair the caracal image resolves to. The epoxy hop keeps
# it (#1277): 24.03 / 3.3 is what neutron's stable/2025.1 gate runs, from the Ubuntu
# 24.04 packages, while RDO's 24.09 / 3.4 and the cloud archive's 25.03 / 3.5 are not;
# and 26.03 is newer than anything epoxy was tested with. The pin is not
# housekeeping: core/neutron/Makefile builds the DR-SNAT-patched ovn-northd from the
# ovn24.03-24.03.8-31.el9s src rpm and core/neutron/ovn_patch/$(HEX_DIST) ships that
# binary, so letting the RPMs float would put a northd built from one OVN release next
# to an ovn-controller and an ovn-nb schema from another. Neither package carries an
# Epoch, so the plain name-version form holds -- see core/heavyfs/Makefile on why an
# epoch in LOCKED_DNF silently defeats the pin.
OVN_VER := -24.03.8-31.el9s
OVN_LOCKED_RPMS := ovn24.03$(OVN_VER) ovn24.03-central$(OVN_VER) ovn24.03-host$(OVN_VER)
OVS_LOCKED_RPMS := openvswitch3.3-3.3.8-7.el9s
LOCKED_DNF += $(OVN_LOCKED_RPMS) $(OVS_LOCKED_RPMS)

# Base networking RPMs
ROOTFS_DNF += $(OVS_LOCKED_RPMS) $(OVN_LOCKED_RPMS)

RDOOVN_VERSION := -24.03-1.el9s
ROOTFS_DNF_DL_FROM += https://cbs.centos.org/kojifiles/packages/rdo-openvswitch/3.3/1.el9s/noarch/rdo-ovn$(RDOOVN_VERSION).noarch.rpm
ROOTFS_DNF_DL_FROM += https://cbs.centos.org/kojifiles/packages/rdo-openvswitch/3.3/1.el9s/noarch/rdo-ovn-central$(RDOOVN_VERSION).noarch.rpm
ROOTFS_DNF_DL_FROM += https://cbs.centos.org/kojifiles/packages/rdo-openvswitch/3.3/1.el9s/noarch/rdo-ovn-host$(RDOOVN_VERSION).noarch.rpm

# System requirements formerly pulled in by openstack-neutron RPMs
# handled elsewhere: iptables
# dibbler-client went with neutron 2025.1, which removed the l3 agent's dibbler-based
# IPv6 prefix delegation and the dibbler filters from rootwrap.filters.
ROOTFS_DNF += dnsmasq dnsmasq-utils radvd conntrack-tools keepalived haproxy ipset iputils iproute-tc libreswan sudo

NEUTRON_SRCDIR := $(ROOTDIR)$(NEXT_OPENSTACK_HOME_DIR)/lib/python$(NEXT_PYTHON_VER)/site-packages/neutron
NEUTRON_PATCHDIR := $(COREDIR)/neutron/$(NEXT_OPENSTACK_RELEASE)_patch
NEUTRON_VPNAAS_SRCDIR := $(ROOTDIR)$(NEXT_OPENSTACK_HOME_DIR)/lib/python$(NEXT_PYTHON_VER)/site-packages/neutron_vpnaas
NEUTRON_VPNAAS_PATCHDIR := $(COREDIR)/neutron/$(NEXT_OPENSTACK_RELEASE)_vpnaas_patch
NEUTRON_CONFDIR := $(ROOTDIR)/etc/neutron

OVN_PATCHDIR := $(COREDIR)/neutron/ovn_patch/$(HEX_DIST)

# https://releases.openstack.org/caracal/index.html#caracal-neutron-vpnaas-dashboard
# Horizon plugins are not in the upper-constraints (that file only covers libraries),
# so the pin is explicit. It replaces a $(OPS_GITHUB_BRANCH_02) clone, whose version
# was whatever the branch tip was on build day.
NEUTRON_VPNAAS_DASHBOARD_VER := 10.0.0

# neutron runs out of the epoxy venv, not the caracal one it shared with the rest of
# the 2024.1 services. neutron 26.0.6 is the newest 2025.1 release, and neutron-vpnaas
# 26.0.0 and networking-baremetal 6.5.0 the only 2025.1 releases of theirs. None of
# them can be installed beside manila/cyborg/heat: neutron 26.0.6 requires os-ken 3.0
# and ovsdbapp 2.11, and neutron-vpnaas 26.0.0 neutron-lib 3.18, where the caracal venv
# holds 2.8.2, 2.6.1 and 3.11.1 -- and openstack-heat resolves neutron-lib out of that
# venv too. So all three move into /opt/openstack-epoxy, the same shape as their
# caracal hop (#628), one release on, with keystone (#657), glance (#656), cinder
# (#655) and nova with placement (#653) as the venv's other occupants. Resolved against
# os-epoxy-pip-upper-constraints.txt they add ten packages there -- the same ten they
# added to the caracal venv -- and change no version those services already hold.
#
# The /usr/bin/neutron-* symlinks, and ironic.mk's /usr/bin/ironic-neutron-agent, are
# the only thing outside this venv that has to follow: the service units,
# config_neutron.cpp and hex_sdk reach neutron through them.
#
# networking-baremetal has to be pinned rather than left to resolve: the epoxy
# constraints file does not carry it, so an unqualified name resolves to whatever is
# newest on PyPI.
#
# NOTE: never pip install the standalone 'networking-ovn' package here -- its OVN
# ML2 driver was merged into neutron since Ussuri, and installing both registers two
# conflicting 'ovn' entry points that crash-loop neutron-server. networking-baremetal
# provides the 'baremetal' ML2 driver that config_neutron.cpp always references;
# unlike on RPM, pip won't pull it in transitively, so it must stay listed
# explicitly below.
#
# Three packages have to be named because neutron's requirements ask for none of them
# and pip will not pull them in transitively:
# PyMySQL: config_neutron.cpp writes a mysql+pymysql:// connection
# oslo.messaging[kafka]: config_neutron.cpp points the notification transport at
#   kafka://
# python-memcached: config_neutron.cpp writes [keystone_authtoken] memcached_servers,
#   which keystonemiddleware serves through memcache
# keystone.mk, glance.mk, cinder.mk and nova.mk install all three into this venv too,
# but a dependency nothing asks for is one that disappears silently -- in the caracal
# venv neutron only ever had them because other components named them.
#
# neutron-vpnaas comes from PyPI, as it has since the caracal hop retired the
# bigstack-oss fork. 2025.1 also took upstream most of the libreswan 4.x adaptation that
# hop had to carry, so $(NEUTRON_VPNAAS_PATCHDIR) is down to the detailed-logging
# option libreswan 4 renamed; see the note there.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(NEXT_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		neutron==26.0.6 \
		neutron-vpnaas==26.0.0 \
		networking-baremetal==6.5.0 \
		PyMySQL \
		\"oslo.messaging[kafka]\" \
		python-memcached"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries
	$(Q)# /usr/bin/neutron and /usr/bin/neutron-debug are deliberately absent: the
	$(Q)# neutron CLI went with python-neutronclient 11.0.0 and neutron-debug with
	$(Q)# neutron 24.0.0. core/sdk_sh/modules/sdk_os.sh reaches neutron through the
	$(Q)# openstack CLI instead. neutron 2025.1 removed three more console scripts and
	$(Q)# they are gone from this list with them: neutron-linuxbridge-agent and
	$(Q)# neutron-linuxbridge-cleanup (the linuxbridge ML2 driver) and neutron-pd-notify
	$(Q)# (dibbler prefix delegation). Its two new ones, neutron-ovn-maintenance-worker
	$(Q)# and neutron-periodic-workers, are the separate processes a uWSGI-served API
	$(Q)# needs; the eventlet neutron-server cube runs still starts both kinds of worker
	$(Q)# itself, so they are not linked.
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-api /usr/bin/neutron-api
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-db-manage /usr/bin/neutron-db-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-dhcp-agent /usr/bin/neutron-dhcp-agent
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-ipset-cleanup /usr/bin/neutron-ipset-cleanup
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-keepalived-state-change /usr/bin/neutron-keepalived-state-change
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-l3-agent /usr/bin/neutron-l3-agent
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-macvtap-agent /usr/bin/neutron-macvtap-agent
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-metadata-agent /usr/bin/neutron-metadata-agent
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-metering-agent /usr/bin/neutron-metering-agent
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-netns-cleanup /usr/bin/neutron-netns-cleanup
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-openvswitch-agent /usr/bin/neutron-openvswitch-agent
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-ovn-agent /usr/bin/neutron-ovn-agent
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-ovn-db-sync-util /usr/bin/neutron-ovn-db-sync-util
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-ovn-metadata-agent /usr/bin/neutron-ovn-metadata-agent
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-ovn-migration-mtu /usr/bin/neutron-ovn-migration-mtu
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-ovs-cleanup /usr/bin/neutron-ovs-cleanup
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-remove-duplicated-port-bindings /usr/bin/neutron-remove-duplicated-port-bindings
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-rootwrap /usr/bin/neutron-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-rootwrap-daemon /usr/bin/neutron-rootwrap-daemon
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-rpc-server /usr/bin/neutron-rpc-server
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-sanitize-port-binding-profile-allocation /usr/bin/neutron-sanitize-port-binding-profile-allocation
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-sanitize-port-mac-addresses /usr/bin/neutron-sanitize-port-mac-addresses
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-sanity-check /usr/bin/neutron-sanity-check
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-server /usr/bin/neutron-server
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-sriov-nic-agent /usr/bin/neutron-sriov-nic-agent
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-status /usr/bin/neutron-status
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-usage-audit /usr/bin/neutron-usage-audit
	$(Q)# for neutron-vpnaas
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-ovn-vpn-agent /usr/bin/neutron-ovn-vpn-agent
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-vpn-netns-wrapper /usr/bin/neutron-vpn-netns-wrapper

# prepare the build directory and configuration templates
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/neutron
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/neutron

# set up the neutron-vpnaas VPN panel
#
# The dashboard is a horizon plugin, so it lives where horizon lives: #636 moved
# horizon into the caracal venv, and 10.0.0 -- the 2024.1 dashboard -- is what wants a
# caracal horizon. It talks to neutron over the API, which is why it is free to sit a
# release behind the service: it stays here, beside the served dashboard, until horizon
# makes its own epoxy hop.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		neutron-vpnaas-dashboard==$(NEUTRON_VPNAAS_DASHBOARD_VER)
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# generate default configurations and stage files
rootfs_install::
	$(Q)# copy statutory configuration templates from core directory
	$(Q)cp -f $(COREDIR)/neutron/neutron-dist.conf $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/dhcp_agent.ini.sample $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/l3_agent.ini.sample $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/macvtap_agent.ini.sample $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/metadata_agent.ini.sample $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/metering_agent.ini.sample $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/ml2_conf.ini.sample $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron.conf.sample $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron_ovn_metadata_agent.ini.sample $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/openvswitch_agent.ini.sample $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/ovn.ini.sample $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/ovn_agent.ini.sample $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/sriov_agent.ini.sample $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-sudoers $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-destroy-patch-ports.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-dhcp-agent.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-l3-agent.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-macvtap-agent.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-metadata-agent.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-metering-agent.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-netns-cleanup.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-openvswitch-agent.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-ovn-agent.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-ovn-metadata-agent.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-ovs-cleanup.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-rpc-server.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-server.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-sriov-nic-agent.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-enable-bridge-firewall.sh $(ROOTDIR)/tmp/neutron/

# install system directories and production files
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 /usr/share/neutron/rootwrap
	$(Q)# api-paste.ini, rootwrap.conf and rootwrap.d/rootwrap.filters are upstream
	$(Q)# data the neutron wheel already installs under the venv prefix through its
	$(Q)# setup.cfg data_files, and all three are byte-identical to what the tree used
	$(Q)# to carry -- so they are installed from there rather than kept as a second
	$(Q)# copy that only moves when someone remembers to re-copy it. (26.0.6's
	$(Q)# rootwrap.filters differs from 24.2.2's by the removed dibbler filters and an
	$(Q)# added conntrackd one; the other two are unchanged.) Ordering is safe:
	$(Q)# the pip install that creates the venv is an earlier rootfs_install:: block in
	$(Q)# this file, and double-colon rules run in definition order.
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 $(NEXT_OPENSTACK_HOME_DIR)/etc/neutron/rootwrap.d/rootwrap.filters /usr/share/neutron/rootwrap/rootwrap.filters
	$(Q)# install base configurations
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/neutron
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 $(NEXT_OPENSTACK_HOME_DIR)/etc/neutron/api-paste.ini /etc/neutron/api-paste.ini
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 $(NEXT_OPENSTACK_HOME_DIR)/etc/neutron/rootwrap.conf /etc/neutron/rootwrap.conf
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/neutron/plugins/ml2
	$(Q)chroot $(ROOTDIR) cp -f /tmp/neutron/neutron.conf.sample /etc/neutron/neutron.conf
	$(Q)chroot $(ROOTDIR) cp -f /tmp/neutron/ovn.ini.sample /etc/neutron/ovn.ini
	$(Q)chroot $(ROOTDIR) cp -f /tmp/neutron/dhcp_agent.ini.sample /etc/neutron/dhcp_agent.ini
	$(Q)chroot $(ROOTDIR) cp -f /tmp/neutron/l3_agent.ini.sample /etc/neutron/l3_agent.ini
	$(Q)chroot $(ROOTDIR) cp -f /tmp/neutron/metadata_agent.ini.sample /etc/neutron/metadata_agent.ini
	$(Q)chroot $(ROOTDIR) cp -f /tmp/neutron/metering_agent.ini.sample /etc/neutron/metering_agent.ini
	$(Q)chroot $(ROOTDIR) cp -f /tmp/neutron/neutron_ovn_metadata_agent.ini.sample /etc/neutron/neutron_ovn_metadata_agent.ini
	$(Q)chroot $(ROOTDIR) cp -f /tmp/neutron/ml2_conf.ini.sample /etc/neutron/plugins/ml2/ml2_conf.ini
	$(Q)chroot $(ROOTDIR) cp -f /tmp/neutron/openvswitch_agent.ini.sample /etc/neutron/plugins/ml2/openvswitch_agent.ini
	$(Q)chroot $(ROOTDIR) cp -f /tmp/neutron/sriov_agent.ini.sample /etc/neutron/plugins/ml2/sriov_agent.ini
	$(Q)chroot $(ROOTDIR) cp -f /tmp/neutron/ovn_agent.ini.sample /etc/neutron/plugins/ml2/ovn_agent.ini
	$(Q)# for the backward compatibility, now networking-ovn is merged into neutron
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/neutron/plugins/networking-ovn
	$(Q)chroot $(ROOTDIR) ln -sf /etc/neutron/neutron_ovn_metadata_agent.ini /etc/neutron/plugins/networking-ovn/networking-ovn-metadata-agent.ini
	$(Q)chroot $(ROOTDIR) ln -sf /etc/neutron/ovn.ini /etc/neutron/plugins/networking-ovn/networking-ovn.ini
	$(Q)chroot $(ROOTDIR) ln -sf /usr/bin/neutron-ovn-metadata-agent /usr/bin/networking-ovn-metadata-agent
	$(Q)# install security configurations
	$(Q)chroot $(ROOTDIR) install -p -D -m 440 /tmp/neutron/neutron-sudoers /etc/sudoers.d/neutron
	$(Q)# install systemd unit files
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-destroy-patch-ports.service /usr/lib/systemd/system/neutron-destroy-patch-ports.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-dhcp-agent.service /usr/lib/systemd/system/neutron-dhcp-agent.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-l3-agent.service /usr/lib/systemd/system/neutron-l3-agent.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-macvtap-agent.service /usr/lib/systemd/system/neutron-macvtap-agent.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-metadata-agent.service /usr/lib/systemd/system/neutron-metadata-agent.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-metering-agent.service /usr/lib/systemd/system/neutron-metering-agent.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-netns-cleanup.service /usr/lib/systemd/system/neutron-netns-cleanup.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-openvswitch-agent.service /usr/lib/systemd/system/neutron-openvswitch-agent.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-ovn-agent.service /usr/lib/systemd/system/neutron-ovn-agent.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-ovn-metadata-agent.service /usr/lib/systemd/system/neutron-ovn-metadata-agent.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-ovs-cleanup.service /usr/lib/systemd/system/neutron-ovs-cleanup.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-rpc-server.service /usr/lib/systemd/system/neutron-rpc-server.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-server.service /usr/lib/systemd/system/neutron-server.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-sriov-nic-agent.service /usr/lib/systemd/system/neutron-sriov-nic-agent.service
	$(Q)# for the backward compatibility
	$(Q)chroot $(ROOTDIR) ln -sf /usr/lib/systemd/system/neutron-ovn-metadata-agent.service /usr/lib/systemd/system/networking-ovn-metadata-agent.service
	$(Q)# install helper scripts
	$(Q)chroot $(ROOTDIR) install -p -D -m 755 /tmp/neutron/neutron-enable-bridge-firewall.sh /usr/bin/neutron-enable-bridge-firewall.sh
	$(Q)# setup directories
	$(Q)chroot $(ROOTDIR) install -d -m 755 /usr/share/neutron
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/neutron
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/log/neutron
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/run/neutron
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/neutron/kill_scripts
	$(Q)# install dist conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/neutron/neutron-dist.conf /usr/share/neutron/neutron-dist.conf
	$(Q)# create and populate configuration directory for L3 agent that is not accessible for user modification
	$(Q)chroot $(ROOTDIR) mkdir -p /usr/share/neutron/l3_agent
	$(Q)chroot $(ROOTDIR) ln -sf /etc/neutron/l3_agent.ini /usr/share/neutron/l3_agent/l3_agent.conf
	$(Q)# create dist configuration directory for neutron-server (may be filled by advanced services)
	$(Q)chroot $(ROOTDIR) mkdir -p /usr/share/neutron/server
	$(Q)# create configuration directories for all services that can be populated by users with custom *.conf files
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/common
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-server
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-rpc-server
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-ovs-cleanup
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-netns-cleanup
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-macvtap-agent
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-openvswitch-agent
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-dhcp-agent
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-l3-agent
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-metadata-agent
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-metering-agent
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-sriov-nic-agent
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-ovn-metadata-agent
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-ovn-agent

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chown root:neutron /etc/neutron/api-paste.ini
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/neutron/api-paste.ini
	$(Q)chroot $(ROOTDIR) chown root:neutron /etc/neutron/dhcp_agent.ini
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/neutron/dhcp_agent.ini
	$(Q)chroot $(ROOTDIR) chown root:neutron /etc/neutron/l3_agent.ini
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/neutron/l3_agent.ini
	$(Q)chroot $(ROOTDIR) chown root:neutron /etc/neutron/metadata_agent.ini
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/neutron/metadata_agent.ini
	$(Q)chroot $(ROOTDIR) chown root:neutron /usr/share/neutron/neutron-dist.conf
	$(Q)chroot $(ROOTDIR) chown root:neutron /etc/neutron/neutron.conf
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/neutron/neutron.conf
	$(Q)chroot $(ROOTDIR) chown root:neutron /etc/neutron/ovn.ini
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/neutron/ovn.ini
	$(Q)chroot $(ROOTDIR) chown neutron:neutron /var/lib/neutron
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/lib/neutron
	$(Q)chroot $(ROOTDIR) chown neutron:neutron /var/log/neutron
	$(Q)chroot $(ROOTDIR) chmod 0750 /var/log/neutron
	$(Q)chroot $(ROOTDIR) chown neutron:neutron /var/run/neutron
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/run/neutron
	$(Q)chroot $(ROOTDIR) bash -c "chown root:neutron /etc/neutron/plugins/ml2/*.ini"
	$(Q)chroot $(ROOTDIR) bash -c "chmod 0640 /etc/neutron/plugins/ml2/*.ini"
	$(Q)chroot $(ROOTDIR) chown root:neutron /etc/neutron/metering_agent.ini
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/neutron/metering_agent.ini

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/neutron

# install custom files
rootfs_install::
	$(Q)cp -f $(NEUTRON_CONFDIR)/neutron.conf $(NEUTRON_CONFDIR)/neutron.conf.def
	$(Q)chroot $(ROOTDIR) ln -sf /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
	$(Q)cp -f $(NEUTRON_CONFDIR)/plugins/ml2/ml2_conf.ini $(NEUTRON_CONFDIR)/plugins/ml2/ml2_conf.ini.def
	$(Q)cp -f $(NEUTRON_CONFDIR)/neutron_ovn_metadata_agent.ini $(NEUTRON_CONFDIR)/plugins/networking-ovn/networking-ovn-metadata-agent.ini.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/neutron/ovn-plugin.filters ./usr/share/neutron/rootwrap/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/neutron/ovn-controller.service ./lib/systemd/system
	$(Q)$(INSTALL_PROGRAM) $(ROOTDIR) $(OVN_PATCHDIR)/ovn-northd ./usr/bin/

# Chassis first, central last (#1551). OVN supports an ovn-controller newer than
# ovn-northd and the NB/SB databases, never older, and an upgrade roll reboots every
# control node before any compute: so on a hop that moves OVN, an upgraded control node
# keeps running the central it carried across until every chassis runs this image's
# OVN, and ovn_central_switch (sdk_ovn.sh) then moves the cluster over in one step.
#
# The epoxy image does not move OVN (#1277), so it carries no previous central -- no
# /opt/ovn-<minor> tree -- and cube-ovndb-servers, cube-ovn-ctl-compat and the
# ovn-northd drop-in, which only act where that tree is, never engage. They stay
# installed for the next hop that moves OVN, which lays the tree out again the way
# 3.1.20 laid out 23.03's (#1552): the previous minor's schemas unpacked from its
# pinned, checksummed central RPM, never rpm-installed, since two OVN minors own the
# same paths and neither obsoletes the other; the previous image's DR-SNAT-patched
# northd, renamed ovn-northd-<minor>, because ovs-lib's init functions reset PATH
# before ovn-ctl looks the northd up by name; and a copy of this image's ovn-ctl
# pointed at it, because an older ovn-ctl can misread a newer ovsdb-server's
# sync-status -- then re-points OVN_COMPAT_VER in sdk_ovn.sh and the files it names.
#
# The agent symlink is repointed in the image rather than at runtime: the rootfs is a git
# worktree of the image, so a runtime edit of that tracked path would show in git status
# and be stashed away by the next git fan-out.
rootfs_install::
	$(Q)$(INSTALL_SCRIPT) $(ROOTDIR) $(COREDIR)/neutron/cube-ovn-ctl-compat $(COREDIR)/neutron/cube-ovndb-servers ./usr/sbin/
	$(Q)chroot $(ROOTDIR) ln -sf /usr/sbin/cube-ovndb-servers /usr/lib/ocf/resource.d/ovn/ovndb-servers
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/neutron/ovn-northd-compat.conf ./etc/systemd/system/ovn-northd.service.d/

# The carried files are whole modules, each beside the upstream .orig it was made from:
# - plugins/ml2/drivers/ovn/agent/neutron_agent.py: an agent whose chassis record has no
#   hostname reports '-' as its host instead of raising AttributeError.
# - neutron-vpnaas' libreswan_ipsec.py: libreswan 4.x renamed pluto's detailed-logging
#   option, and config_neutron.cpp turns detailed logging on.
rootfs_install::
	$(Q)[ -d $(NEUTRON_PATCHDIR) ] && cp -rf $(NEUTRON_PATCHDIR)/* $(NEUTRON_SRCDIR)/ || /bin/true
	$(Q)[ -d $(NEUTRON_VPNAAS_PATCHDIR) ] && cp -rf $(NEUTRON_VPNAAS_PATCHDIR)/* $(NEUTRON_VPNAAS_SRCDIR)/ || /bin/true

rootfs_install::
	$(Q)for ns in $$(find $(ROOTDIR)/usr/lib/systemd/system/*neutron*.service) ; do sed -i /^Timeout*/d $$ns ; done

# for neutron-vpnaas
rootfs_install::
	$(Q)chroot $(ROOTDIR) ln -sf /etc/neutron/neutron_vpnaas.conf /usr/share/neutron/server/neutron_vpnaas.conf
	$(Q)# Note: The netns wrapper symlink target is updated to the venv bin path
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/neutron-vpn-netns-wrapper /usr/sbin/neutron-vpn-netns-wrapper
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/neutron/neutron_vpnaas.conf ./etc/neutron/neutron_vpnaas.conf.def
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/neutron/vpn_agent.ini ./etc/neutron/vpn_agent.ini.def
	$(Q)# vpnaas.filters is the one filter file that stays carried: the neutron-vpnaas
	$(Q)# wheel ships it too, but upstream's copy authorises
	$(Q)# /usr/local/bin/neutron-vpn-netns-wrapper and cube's wrapper is at /usr/bin.
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/neutron/vpnaas.filters ./usr/share/neutron/rootwrap/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/neutron/neutron-ovn-vpn-agent.service ./lib/systemd/system

# The neutron-vpnaas-dashboard VPN panel is registered by core/horizon/horizon.mk,
# where every dashboard action lives. It was never registered before #609: horizon ran
# under python 3.9 while the plugin was installed venv-only, so ADD_INSTALLED_APPS
# would have failed to import and taken the whole dashboard down with it.
