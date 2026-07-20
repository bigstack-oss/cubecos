# Cube SDK
# neutron installation

RDOOVN_VERSION := -23.03-3.el9s

# Base networking RPMs
ROOTFS_DNF += openvswitch3.1 ovn23.03 ovn23.03-central ovn23.03-host

# System requirements formerly pulled in by openstack-neutron RPMs
# handled elsewhere: iptables
ROOTFS_DNF += dnsmasq dnsmasq-utils radvd dibbler-client conntrack-tools keepalived haproxy ipset iputils iproute-tc libreswan sudo

ROOTFS_DNF_DL_FROM += https://cbs.centos.org/kojifiles/packages/rdo-openvswitch/3.1/3.el9s/noarch/rdo-ovn$(RDOOVN_VERSION).noarch.rpm
ROOTFS_DNF_DL_FROM += https://cbs.centos.org/kojifiles/packages/rdo-openvswitch/3.1/3.el9s/noarch/rdo-ovn-central$(RDOOVN_VERSION).noarch.rpm
ROOTFS_DNF_DL_FROM += https://cbs.centos.org/kojifiles/packages/rdo-openvswitch/3.1/3.el9s/noarch/rdo-ovn-host$(RDOOVN_VERSION).noarch.rpm

NEUTRON_SRCDIR := $(ROOTDIR)/opt/openstack-antelope/lib/python3.10/site-packages/neutron
NEUTRON_PATCHDIR := $(COREDIR)/neutron/$(NEXT_OPENSTACK_RELEASE)_patch
NEUTRON_CONFDIR := $(ROOTDIR)/etc/neutron

OVN_PATCHDIR := $(COREDIR)/neutron/ovn_patch/$(HEX_DIST)

NEUTRON_VPNAAS_REPO_URL := https://github.com/bigstack-oss/neutron-vpnaas.git
NEUTRON_VPNAAS_DASHBOARD_REPO_URL := https://github.com/openstack/neutron-vpnaas-dashboard.git

# install neutron inside the python 3.10 virtual environment
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		neutron==22.2.1 \
		networking-ovn"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron /usr/bin/neutron
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-api /usr/bin/neutron-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-db-manage /usr/bin/neutron-db-manage
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-debug /usr/bin/neutron-debug
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-dhcp-agent /usr/bin/neutron-dhcp-agent
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-ipset-cleanup /usr/bin/neutron-ipset-cleanup
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-keepalived-state-change /usr/bin/neutron-keepalived-state-change
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-l3-agent /usr/bin/neutron-l3-agent
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-linuxbridge-agent /usr/bin/neutron-linuxbridge-agent
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-linuxbridge-cleanup /usr/bin/neutron-linuxbridge-cleanup
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-macvtap-agent /usr/bin/neutron-macvtap-agent
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-metadata-agent /usr/bin/neutron-metadata-agent
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-metering-agent /usr/bin/neutron-metering-agent
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-netns-cleanup /usr/bin/neutron-netns-cleanup
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-openvswitch-agent /usr/bin/neutron-openvswitch-agent
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-ovn-agent /usr/bin/neutron-ovn-agent
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-ovn-db-sync-util /usr/bin/neutron-ovn-db-sync-util
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-ovn-metadata-agent /usr/bin/neutron-ovn-metadata-agent
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-ovn-migration-mtu /usr/bin/neutron-ovn-migration-mtu
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-ovs-cleanup /usr/bin/neutron-ovs-cleanup
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-pd-notify /usr/bin/neutron-pd-notify
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-remove-duplicated-port-bindings /usr/bin/neutron-remove-duplicated-port-bindings
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-rootwrap /usr/bin/neutron-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-rootwrap-daemon /usr/bin/neutron-rootwrap-daemon
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-rpc-server /usr/bin/neutron-rpc-server
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-sanitize-port-binding-profile-allocation /usr/bin/neutron-sanitize-port-binding-profile-allocation
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-sanitize-port-mac-addresses /usr/bin/neutron-sanitize-port-mac-addresses
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-sanity-check /usr/bin/neutron-sanity-check
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-server /usr/bin/neutron-server
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-sriov-nic-agent /usr/bin/neutron-sriov-nic-agent
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-status /usr/bin/neutron-status
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-usage-audit /usr/bin/neutron-usage-audit

# prepare the build directory and configuration templates
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/neutron
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/neutron

# set up forked neutron-vpnaas projects
rootfs_install::
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(NEXT_OPS_GITHUB_BRANCH_02) --depth 1 $(NEUTRON_VPNAAS_REPO_URL) /tmp/neutron/neutron-vpnaas
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		-r /tmp/neutron/neutron-vpnaas/requirements.txt
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/neutron/neutron-vpnaas && \
		/opt/openstack-antelope/bin/python setup.py install"
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(NEXT_OPS_GITHUB_BRANCH_02) --depth 1 $(NEUTRON_VPNAAS_DASHBOARD_REPO_URL) /tmp/neutron/neutron-vpnaas-dashboard
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		-r /tmp/neutron/neutron-vpnaas-dashboard/requirements.txt \
		--no-build-isolation
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/neutron/neutron-vpnaas-dashboard && \
		/opt/openstack-antelope/bin/python setup.py install"

# generate default configurations and stage files
rootfs_install::
	$(Q)# copy statutory configuration templates from core directory
	$(Q)cp -f $(COREDIR)/neutron/neutron-dist.conf $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/dhcp_agent.ini.sample $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/l3_agent.ini.sample $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/linuxbridge_agent.ini.sample $(ROOTDIR)/tmp/neutron/
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
	$(Q)cp -f $(COREDIR)/neutron/rootwrap.filters $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/api-paste.ini $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/rootwrap.conf $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-sudoers $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-destroy-patch-ports.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-dhcp-agent.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-l3-agent.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-linuxbridge-agent.service $(ROOTDIR)/tmp/neutron/
	$(Q)cp -f $(COREDIR)/neutron/neutron-linuxbridge-cleanup.service $(ROOTDIR)/tmp/neutron/
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
	$(Q)cp -f $(COREDIR)/neutron/neutron-l2-agent-sysctl.conf $(ROOTDIR)/tmp/neutron/

# install system directories and production files
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 /usr/share/neutron/rootwrap
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/rootwrap.filters /usr/share/neutron/rootwrap/rootwrap.filters
	$(Q)# install base configurations
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/neutron
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/api-paste.ini /etc/neutron/api-paste.ini
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/rootwrap.conf /etc/neutron/rootwrap.conf
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/neutron/plugins/ml2
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/neutron.conf.sample /etc/neutron/neutron.conf
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/ovn.ini.sample /etc/neutron/ovn.ini
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/dhcp_agent.ini.sample /etc/neutron/dhcp_agent.ini
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/l3_agent.ini.sample /etc/neutron/l3_agent.ini
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/metadata_agent.ini.sample /etc/neutron/metadata_agent.ini
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/metering_agent.ini.sample /etc/neutron/metering_agent.ini
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/neutron_ovn_metadata_agent.ini.sample /etc/neutron/neutron_ovn_metadata_agent.ini
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/linuxbridge_agent.ini.sample /etc/neutron/plugins/ml2/linuxbridge_agent.ini
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/ml2_conf.ini.sample /etc/neutron/plugins/ml2/ml2_conf.ini
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/openvswitch_agent.ini.sample /etc/neutron/plugins/ml2/openvswitch_agent.ini
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/sriov_agent.ini.sample /etc/neutron/plugins/ml2/sriov_agent.ini
	$(Q)cp -f $(ROOTDIR)/tmp/neutron/ovn_agent.ini.sample /etc/neutron/plugins/ml2/ovn_agent.ini
	$(Q)# for the backward compatibility, now networking-ovn is merged into neutron
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/neutron/plugins/networking-ovn
	$(Q)chroot $(ROOTDIR) ln -s /etc/neutron/neutron_ovn_metadata_agent.ini /etc/neutron/plugins/networking-ovn/networking-ovn-metadata-agent.ini
	$(Q)chroot $(ROOTDIR) ln -s /etc/neutron/ovn.ini /etc/neutron/plugins/networking-ovn/networking-ovn.ini
	$(Q)chroot $(ROOTDIR) ln -s /usr/bin/neutron-ovn-metadata-agent /usr/bin/networking-ovn-metadata-agent
	$(Q)# install security configurations
	$(Q)chroot $(ROOTDIR) install -p -D -m 440 /tmp/neutron/neutron-sudoers /etc/sudoers.d/neutron
	$(Q)# install systemd unit files
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-destroy-patch-ports.service /usr/lib/systemd/system/neutron-destroy-patch-ports.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-dhcp-agent.service /usr/lib/systemd/system/neutron-dhcp-agent.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-l3-agent.service /usr/lib/systemd/system/neutron-l3-agent.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-linuxbridge-agent.service /usr/lib/systemd/system/neutron-linuxbridge-agent.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/neutron/neutron-linuxbridge-cleanup.service /usr/lib/systemd/system/neutron-linuxbridge-cleanup.service
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
	$(Q)ln -s /usr/lib/systemd/system/neutron-ovn-metadata-agent.service /usr/lib/systemd/system/networking-ovn-metadata-agent.service
	$(Q)# install helper scripts
	$(Q)chroot $(ROOTDIR) install -p -D -m 755 /tmp/neutron/neutron-enable-bridge-firewall.sh /usr/bin/neutron-enable-bridge-firewall.sh
	$(Q)# setup directories
	$(Q)chroot $(ROOTDIR) install -d -m 755 /usr/share/neutron
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/neutron
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/log/neutron
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/run/neutron
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/neutron/kill_scripts
	$(Q)# install dist conf
	$(Q)install -p -D -m 640 /tmp/neutron/neutron-dist.conf /usr/share/neutron/neutron-dist.conf
	$(Q)# create and populate configuration directory for L3 agent that is not accessible for user modification
	$(Q)chroot $(ROOTDIR) mkdir -p /usr/share/neutron/l3_agent
	$(Q)chroot $(ROOTDIR) ln -s /etc/neutron/l3_agent.ini /usr/share/neutron/l3_agent/l3_agent.conf
	$(Q)# create dist configuration directory for neutron-server (may be filled by advanced services)
	$(Q)chroot $(ROOTDIR) mkdir -p /usr/share/neutron/server
	$(Q)# create configuration directories for all services that can be populated by users with custom *.conf files
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/common
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-server
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-rpc-server
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-ovs-cleanup
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-netns-cleanup
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-linuxbridge-cleanup
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-macvtap-agent
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/neutron/conf.d/neutron-linuxbridge-agent
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

# install custom files and VPNaaS components
rootfs_install::
	$(Q)cp -f $(NEUTRON_CONFDIR)/neutron.conf $(NEUTRON_CONFDIR)/neutron.conf.def
	$(Q)chroot $(ROOTDIR) ln -sf /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
	$(Q)cp -f $(NEUTRON_CONFDIR)/plugins/ml2/ml2_conf.ini $(NEUTRON_CONFDIR)/plugins/ml2/ml2_conf.ini.def
	$(Q)cp -f $(NEUTRON_CONFDIR)/neutron_ovn_metadata_agent.ini $(NEUTRON_CONFDIR)/plugins/networking-ovn/networking-ovn-metadata-agent.ini.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/neutron/ovn-plugin.filters ./usr/share/neutron/rootwrap/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/neutron/ovn-controller.service ./lib/systemd/system
	$(Q)$(INSTALL_PROGRAM) $(ROOTDIR) $(OVN_PATCHDIR)/ovn-northd ./usr/bin/

rootfs_install::
	$(Q)[ -d $(NEUTRON_PATCHDIR) ] && cp -rf $(NEUTRON_PATCHDIR)/* $(NEUTRON_SRCDIR)/ || /bin/true

rootfs_install::
	$(Q)for ns in $$(find $(ROOTDIR)/usr/lib/systemd/system/*neutron*.service) ; do sed -i /^Timeout*/d $$ns ; done

# for neutron-vpnaas
rootfs_install::
	$(Q)chroot $(ROOTDIR) ln -sf /etc/neutron/neutron_vpnaas.conf /usr/share/neutron/server/neutron_vpnaas.conf
	$(Q)# Note: The netns wrapper symlink target is updated to the venv bin path
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/neutron-vpn-netns-wrapper /usr/sbin/neutron-vpn-netns-wrapper
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/neutron/neutron_vpnaas.conf ./etc/neutron/neutron_vpnaas.conf.def
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/neutron/vpn_agent.ini ./etc/neutron/vpn_agent.ini.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/neutron/vpnaas.filters ./usr/share/neutron/rootwrap/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/neutron/neutron-ovn-vpn-agent.service ./lib/systemd/system

# for neutron-vpnaas-dashboard
rootfs_install::
	$(Q)cp -f $(PIPS_DIR)/neutron-vpnaas-dashboard.git/neutron_vpnaas_dashboard/enabled/_7100*.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
