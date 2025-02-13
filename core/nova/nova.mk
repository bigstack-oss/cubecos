# Cube SDK
# nova installation

# spice html5 proxy doesn't work well, improve in the future
# $(call PROJ_INSTALL_APT,,dosfstools nova-api nova-conductor nova-consoleauth nova-novncproxy nova-spicehtml5proxy spice-html5 spice-vdagent nova-scheduler nova-placement-api nova-compute)

ROOTFS_DNF += libvirt
ROOTFS_DNF += dosfstools python3-libvirt ksmtuned qemu-kvm-device-display-virtio-gpu-pci qemu-kvm-device-display-virtio-gpu qemu-guest-agent
ROOTFS_DNF_NOARCH += openstack-nova-api openstack-nova-conductor openstack-nova-novncproxy openstack-nova-scheduler openstack-nova-compute openstack-placement-api python3-osc-placement

NOVA_SRCDIR := $(ROOTDIR)/usr/lib/python3.9/site-packages/nova
NOVA_PATCHDIR := $(COREDIR)/nova/$(OPENSTACK_RELEASE)_patch

rootfs_install::
	$(Q)[ -d $(NOVA_PATCHDIR) ] && cp -rf $(NOVA_PATCHDIR)/* $(NOVA_SRCDIR)/ || /bin/true

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/nova/nova.d
	$(Q)rm -f $(ROOTDIR)/etc/httpd/conf.d/00-placement-api.conf
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/nova/placement-api-wsgi.conf.in ./etc/httpd/conf.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/nova/openstack-nova-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/nova/openstack-nova-scheduler.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/nova/openstack-nova-conductor.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/nova/openstack-nova-compute.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/nova/openstack-nova-ironic-compute.service ./lib/systemd/system
	$(Q)cp -f $(ROOTDIR)/etc/placement/placement.conf $(ROOTDIR)/etc/placement/placement.conf.def
	$(Q)mv $(ROOTDIR)/etc/placement/policy.json $(ROOTDIR)/etc/placement/policy.json.orig
	$(Q)cp -f $(ROOTDIR)/etc/nova/nova.conf $(ROOTDIR)/etc/nova/nova.conf.def
	$(Q)chroot $(ROOTDIR) systemctl disable mdmonitor libvirtd udisks2
	$(Q)chroot $(ROOTDIR) systemctl disable qemu-guest-agent virtqemud ksm ksmtuned || true
#	$(Q)chroot $(ROOTDIR) systemctl disable openstack-nova-spiceproxy
	$(Q)chmod 0755 $(ROOTDIR)/usr/share/polkit-1/rules.d $(ROOTDIR)/etc/polkit-1/rules.d

rootfs_install::
	$(Q)for ns in $$(find $(ROOTDIR)/usr/lib/systemd/system/*nova*.service) ; do sed -i /^Timeout*/d $$ns ; done

rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /var/lib/nova/instances
	$(Q)chroot $(ROOTDIR) ln -sf /mnt/cephfs/nova/instances /var/lib/nova/instances
