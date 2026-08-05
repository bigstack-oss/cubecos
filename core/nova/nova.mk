# Cube SDK
# nova installation

# spice html5 proxy doesn't work well, improve in the future
# $(call PROJ_INSTALL_APT,,dosfstools nova-api nova-conductor nova-consoleauth nova-novncproxy nova-spicehtml5proxy spice-html5 spice-vdagent nova-scheduler nova-placement-api nova-compute)

# libvirt is held at 11.10.0-14.el9. A version in ROOTFS_DNF alone does not hold
# it: installdnf runs `dnf download --resolve` and then localinstalls whatever
# landed in RPMS, and python3-libvirt and virt-v2v require the sonames
# libvirt.so.0 / libvirt-lxc.so.0 rather than a package version. Every release in
# the repos (-4/-12/-13/-14/-16) provides those sonames identically, so the
# download pulls -16 for part of the tree next to the -14 the pin asked for.
# installdnf's duplicate pass then keeps the *newer* file of each pair unless the
# older one is listed in locked_rpms.txt, i.e. unless it is in LOCKED_DNF -- so
# the -14 subpackages get deleted and localinstall dies with
# "cannot install both libvirt-client-11.10.0-16.el9 from @commandline and
# libvirt-client-11.10.0-14.el9 from appstream".
#
# So the whole tree has to be listed, the way core/heavyfs/Makefile does it for
# qemu and core/pacemaker/pacemaker.mk for pacemaker. ROOTFS_DNF installs, and
# LOCKED_DNF is what makes the duplicate pass drop -16 instead of -14.
LIBVIRT_VER := -11.10.0-14.el9
LIBVIRT_LOCKED_RPMS := libvirt$(LIBVIRT_VER) libvirt-libs$(LIBVIRT_VER) libvirt-devel$(LIBVIRT_VER)
LIBVIRT_LOCKED_RPMS += libvirt-client$(LIBVIRT_VER) libvirt-client-qemu$(LIBVIRT_VER)
LIBVIRT_LOCKED_RPMS += libvirt-daemon$(LIBVIRT_VER) libvirt-daemon-common$(LIBVIRT_VER)
LIBVIRT_LOCKED_RPMS += libvirt-daemon-lock$(LIBVIRT_VER) libvirt-daemon-log$(LIBVIRT_VER)
LIBVIRT_LOCKED_RPMS += libvirt-daemon-proxy$(LIBVIRT_VER) libvirt-daemon-plugin-lockd$(LIBVIRT_VER)
LIBVIRT_LOCKED_RPMS += libvirt-daemon-config-network$(LIBVIRT_VER) libvirt-daemon-config-nwfilter$(LIBVIRT_VER)
LIBVIRT_LOCKED_RPMS += libvirt-daemon-driver-interface$(LIBVIRT_VER) libvirt-daemon-driver-network$(LIBVIRT_VER)
LIBVIRT_LOCKED_RPMS += libvirt-daemon-driver-nodedev$(LIBVIRT_VER) libvirt-daemon-driver-nwfilter$(LIBVIRT_VER)
LIBVIRT_LOCKED_RPMS += libvirt-daemon-driver-qemu$(LIBVIRT_VER) libvirt-daemon-driver-secret$(LIBVIRT_VER)
LIBVIRT_LOCKED_RPMS += libvirt-daemon-driver-storage$(LIBVIRT_VER) libvirt-daemon-driver-storage-core$(LIBVIRT_VER)
LIBVIRT_LOCKED_RPMS += libvirt-daemon-driver-storage-disk$(LIBVIRT_VER) libvirt-daemon-driver-storage-iscsi$(LIBVIRT_VER)
LIBVIRT_LOCKED_RPMS += libvirt-daemon-driver-storage-logical$(LIBVIRT_VER) libvirt-daemon-driver-storage-mpath$(LIBVIRT_VER)
LIBVIRT_LOCKED_RPMS += libvirt-daemon-driver-storage-rbd$(LIBVIRT_VER) libvirt-daemon-driver-storage-scsi$(LIBVIRT_VER)
LOCKED_DNF += $(LIBVIRT_LOCKED_RPMS)

# Core hypervisor and system dependencies from the Antelope spec
ROOTFS_DNF += $(LIBVIRT_LOCKED_RPMS) dosfstools python3-libvirt ksmtuned virt-v2v qemu-kvm ipmitool openssh-clients rsync xorriso sudo
# handled elsewhere: iptables
ROOTFS_DNF_NOARCH += iptables-services novnc

NOVA_SRCDIR := $(ROOTDIR)/opt/openstack-antelope/lib/python3.10/site-packages/nova
NOVA_PATCHDIR := $(COREDIR)/nova/$(NEXT_OPENSTACK_RELEASE)_patch

# install nova inside the python 3.10 virtual environment
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			nova==27.5.1 \
			python-novaclient \
			python-cinderclient \
			python-glanceclient \
			python-neutronclient \
			openstack-placement \
			osc-placement \
			osprofiler \
			uwsgi \
			libvirt-python \
			oslo.privsep"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link Nova binaries
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova /usr/bin/nova
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-api /usr/bin/nova-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-api-metadata /usr/bin/nova-api-metadata
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-api-os-compute /usr/bin/nova-api-os-compute
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-api-wsgi /usr/bin/nova-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-compute /usr/bin/nova-compute
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-conductor /usr/bin/nova-conductor
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-manage /usr/bin/nova-manage
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-metadata-wsgi /usr/bin/nova-metadata-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-novncproxy /usr/bin/nova-novncproxy
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-policy /usr/bin/nova-policy
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-rootwrap /usr/bin/nova-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-rootwrap-daemon /usr/bin/nova-rootwrap-daemon
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-scheduler /usr/bin/nova-scheduler
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-serialproxy /usr/bin/nova-serialproxy
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-spicehtml5proxy /usr/bin/nova-spicehtml5proxy
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/nova-status /usr/bin/nova-status
	$(Q)# Link Placement binaries (since they were removed from RPMs)
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/placement-api /usr/bin/placement-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/placement-manage /usr/bin/placement-manage
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/placement-status /usr/bin/placement-status
	$(Q)# Link the uWSGI binary for Placement WSGI
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/uwsgi /usr/bin/uwsgi

# Link the venv's privsep-helper into /usr/bin.
#
# oslo.privsep escalates by running `sudo privsep-helper`, resolved off sudo's
# secure_path (/sbin:/bin:/usr/sbin:/usr/bin), which never contains the venv's bin --
# so the bare name has to exist there. It is listed in the pip install above rather
# than left transitive for the same reason python3-designateclient is named in
# core/designate/designate.mk: a dependency nothing asks for is one that disappears
# silently.
#
# This link was deliberately deferred until every privsep user had moved into the
# venv, because /usr/bin/privsep-helper used to be a *python 3.9* binary owned by
# python3-oslo-privsep, shared by every rootwrap caller:
#
#   # rpm -qf /usr/bin/privsep-helper
#   python3-oslo-privsep-2.7.0-1.el9s.noarch
#   # dnf repoquery --installed --whatrequires python3-oslo-privsep
#   openstack-ironic-common, python3-cinder-common, python3-glance-store,
#   python3-manila, python3-neutron, python3-nova, python3-os-brick, python3-os-vif
#
# Pointing it at the 3.10 helper while any of those still ran on 3.9 would have
# broken them. All eight have since moved, python3-oslo-privsep is no longer
# installed, and `python3 -c "import oslo_privsep"` fails on the system python --
# so there is no 3.9 consumer left and the link is now unambiguously correct.
#
# It is also load-bearing: with no /usr/bin/privsep-helper at all,
# neutron-ovn-metadata-agent crash-looped on
# "FailedToDropPrivileges: privsep helper command exited non-zero (96)" and
# `cluster check` reported "Network NG [ neutron(3 metadata not all up) ]".
rootfs_install::
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/privsep-helper /usr/bin/privsep-helper

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/nova
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/nova

# generate default configurations and stage files
rootfs_install::
	$(Q)cp -f $(COREDIR)/nova/nova-dist.conf $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/nova.conf.sample $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/nova-compute.conf.sample $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/policy.yaml.sample $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/api-paste.ini $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/rootwrap.conf $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/policy.json $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/release $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/placement-dist.conf $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/placement.conf.sample $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/placement-policy.yaml.sample $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/placement-policy.json $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/placement-api.conf $(ROOTDIR)/tmp/nova/
	$(Q)# copy systemd unit file templates
	$(Q)cp -f $(COREDIR)/nova/openstack-nova-api.service $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/openstack-nova-compute.service $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/openstack-nova-scheduler.service $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/openstack-nova-metadata-api.service $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/openstack-nova-conductor.service $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/openstack-nova-spicehtml5proxy.service $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/openstack-nova-novncproxy.service $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/openstack-nova-serialproxy.service $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/openstack-nova-os-compute-api.service $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/openstack-nova-ironic-compute.service $(ROOTDIR)/tmp/nova/
	$(Q)# copy security configurations
	$(Q)cp -f $(COREDIR)/nova/nova-sudoers $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/nova-ifc-template $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/rootwrap_compute.filters $(ROOTDIR)/tmp/nova/

# install system directories and production files
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/nova
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/nova/buckets
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/nova/instances
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/nova/keys
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/nova/networks
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/nova/tmp
	$(Q)chroot $(ROOTDIR) install -d -m 750 /var/log/nova
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/nova
	$(Q)chroot $(ROOTDIR) install -d -m 750 /var/log/placement
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/placement
	$(Q)chroot $(ROOTDIR) install -d -m 755 /usr/share/nova
	$(Q)chroot $(ROOTDIR) install -d -m 755 /usr/share/placement
	$(Q)# install configurations
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/nova-dist.conf /usr/share/nova/nova-dist.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/nova.conf.sample /etc/nova/nova.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/nova-compute.conf.sample /etc/nova/nova-compute.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/policy.yaml.sample /etc/nova/policy.yaml.sample
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/api-paste.ini /etc/nova/api-paste.ini
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/rootwrap.conf /etc/nova/rootwrap.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/policy.json /etc/nova/policy.json
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/nova/release /etc/nova/release
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/placement-dist.conf /usr/share/placement/placement-dist.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/placement.conf.sample /etc/placement/placement.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/placement-policy.yaml.sample /etc/placement/policy.yaml.sample
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/placement-policy.json /etc/placement/policy.json
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/placement-api.conf /etc/httpd/conf.d/00-placement-api.conf
	$(Q)# install systemd unit files
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/nova/openstack-nova-api.service /usr/lib/systemd/system/openstack-nova-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/nova/openstack-nova-compute.service /usr/lib/systemd/system/openstack-nova-compute.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/nova/openstack-nova-scheduler.service /usr/lib/systemd/system/openstack-nova-scheduler.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/nova/openstack-nova-metadata-api.service /usr/lib/systemd/system/openstack-nova-metadata-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/nova/openstack-nova-conductor.service /usr/lib/systemd/system/openstack-nova-conductor.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/nova/openstack-nova-spicehtml5proxy.service /usr/lib/systemd/system/openstack-nova-spicehtml5proxy.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/nova/openstack-nova-novncproxy.service /usr/lib/systemd/system/openstack-nova-novncproxy.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/nova/openstack-nova-serialproxy.service /usr/lib/systemd/system/openstack-nova-serialproxy.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/nova/openstack-nova-os-compute-api.service /usr/lib/systemd/system/openstack-nova-os-compute-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/nova/openstack-nova-ironic-compute.service /usr/lib/systemd/system/openstack-nova-ironic-compute.service
	$(Q)# install security configurations
	$(Q)chroot $(ROOTDIR) install -p -D -m 440 /tmp/nova/nova-sudoers /etc/sudoers.d/nova
	$(Q)# install pid directory
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/run/nova
	$(Q)# install template files
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/nova/nova-ifc-template /usr/share/nova/interfaces.template
	$(Q)# install rootwrap filters
	$(Q)chroot $(ROOTDIR) install -d -m 755 /usr/share/nova/rootwrap
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/nova/rootwrap_compute.filters /usr/share/nova/rootwrap/compute.filters

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chown root:nova /usr/share/nova/nova-dist.conf
	$(Q)chroot $(ROOTDIR) chown root:nova /etc/nova/nova.conf
	$(Q)chroot $(ROOTDIR) chown root:nova /etc/nova/nova-compute.conf
	$(Q)chroot $(ROOTDIR) chown root:nova /etc/nova/api-paste.ini
	$(Q)chroot $(ROOTDIR) chown root:nova /etc/nova/rootwrap.conf
	$(Q)chroot $(ROOTDIR) chown root:nova /etc/nova/policy.json
	$(Q)chroot $(ROOTDIR) chown nova:root /var/log/nova
	$(Q)chroot $(ROOTDIR) chmod 0750 /var/log/nova
	$(Q)chroot $(ROOTDIR) chown nova:root /var/run/nova
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/run/nova
	$(Q)chroot $(ROOTDIR) chown -R nova:nova /var/lib/nova
	$(Q)chroot $(ROOTDIR) chown root:placement /usr/share/placement/placement-dist.conf
	$(Q)chroot $(ROOTDIR) chown root:placement /etc/placement/placement.conf
	$(Q)chroot $(ROOTDIR) chown root:placement /etc/placement/policy.json
	$(Q)chroot $(ROOTDIR) chown placement:root /var/log/placement
	$(Q)chroot $(ROOTDIR) chmod 0750 /var/log/placement

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/nova

# install custom files and run deployment overrides
rootfs_install::
	$(Q)[ -d $(NOVA_PATCHDIR) ] && cp -rf $(NOVA_PATCHDIR)/* $(NOVA_SRCDIR)/ || /bin/true

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/nova/nova.d
	$(Q)rm -f $(ROOTDIR)/etc/httpd/conf.d/00-placement-api.conf
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/nova/placement-api-wsgi.conf.in ./etc/httpd/conf.d/
	$(Q)cp -f $(ROOTDIR)/etc/placement/placement.conf $(ROOTDIR)/etc/placement/placement.conf.def
	$(Q)mv $(ROOTDIR)/etc/placement/policy.json $(ROOTDIR)/etc/placement/policy.json.orig
	$(Q)cp -f $(ROOTDIR)/etc/nova/nova.conf $(ROOTDIR)/etc/nova/nova.conf.def
	$(Q)chroot $(ROOTDIR) systemctl disable mdmonitor libvirtd udisks2
	$(Q)chroot $(ROOTDIR) systemctl disable qemu-guest-agent virtqemud ksm ksmtuned || true
	$(Q)chroot $(ROOTDIR) systemctl disable openstack-nova-spicehtml5proxy
	$(Q)chroot $(ROOTDIR) systemctl disable openstack-nova-serialproxy
	$(Q)chmod 0755 $(ROOTDIR)/usr/share/polkit-1/rules.d $(ROOTDIR)/etc/polkit-1/rules.d

rootfs_install::
	$(Q)for ns in $$(find $(ROOTDIR)/usr/lib/systemd/system/*nova*.service) ; do sed -i /^Timeout*/d $$ns ; done

rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /var/lib/nova/instances
	$(Q)chroot $(ROOTDIR) ln -sf /mnt/cephfs/nova/instances /var/lib/nova/instances

rootfs_install::
	$(Q)cp -f $(COREDIR)/nova/placement-uwsgi.ini $(ROOTDIR)/etc/placement/placement-uwsgi.ini
	$(Q)chroot $(ROOTDIR) chown root:placement /etc/placement/placement-uwsgi.ini
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/placement/placement-uwsgi.ini
	$(Q)cp -f $(COREDIR)/nova/openstack-placement-api.service $(ROOTDIR)/usr/lib/systemd/system/openstack-placement-api.service
	$(Q)chroot $(ROOTDIR) chmod 0644 /usr/lib/systemd/system/openstack-placement-api.service
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/placement
	$(Q)chroot $(ROOTDIR) chown placement:apache /var/lib/placement
	$(Q)chroot $(ROOTDIR) chmod 770 /var/lib/placement
