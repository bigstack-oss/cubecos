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

NOVA_SRCDIR := $(ROOTDIR)$(CARACAL_OPENSTACK_HOME_DIR)/lib/python$(CARACAL_PYTHON_VER)/site-packages/nova
NOVA_PATCHDIR := $(COREDIR)/nova/$(CARACAL_OPENSTACK_RELEASE)_patch

# nova and placement run out of the caracal venv. nova 29.4.0 is the last 2024.1
# release and openstack-placement 11.0.1 its counterpart; both pull only new
# packages into $(CARACAL_OPENSTACK_HOME_DIR) -- 17 of them, changing no version
# skyline, keystone, glance or cinder already holds -- so the hop costs the other
# occupants nothing.
#
# It has to be a different venv rather than a version bump in place: neutron,
# manila, masakari, cyborg, ironic and the rest of the 2023.1 set share
# /opt/openstack-antelope, and installing nova 29.4.0 beside them would have taken
# os-vif to 3.5.0 and oslo.privsep to 3.3.0 under neutron.
#
# libvirt-python is the one C extension here and it compiles against whatever
# libvirt-devel headers are present, so os-caracal-pip-upper-constraints.txt carries
# the same deliberate 11.10.0 bump the antelope file got, matching the
# libvirt-11.10.0-14.el9 held above. Left at caracal's own 10.0.0 the build dies deep
# in generator.py on missing type converters, which reads like a code bug.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(CARACAL_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			nova==29.4.0 \
			openstack-placement==11.0.1 \
			python-novaclient \
			python-cinderclient \
			python-glanceclient \
			python-neutronclient \
			osc-placement \
			osprofiler \
			uwsgi \
			libvirt-python \
			oslo.privsep"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link Nova binaries
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova /usr/bin/nova
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-api /usr/bin/nova-api
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-api-metadata /usr/bin/nova-api-metadata
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-api-os-compute /usr/bin/nova-api-os-compute
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-api-wsgi /usr/bin/nova-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-compute /usr/bin/nova-compute
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-conductor /usr/bin/nova-conductor
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-manage /usr/bin/nova-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-metadata-wsgi /usr/bin/nova-metadata-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-novncproxy /usr/bin/nova-novncproxy
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-policy /usr/bin/nova-policy
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-rootwrap /usr/bin/nova-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-rootwrap-daemon /usr/bin/nova-rootwrap-daemon
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-scheduler /usr/bin/nova-scheduler
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-serialproxy /usr/bin/nova-serialproxy
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-spicehtml5proxy /usr/bin/nova-spicehtml5proxy
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/nova-status /usr/bin/nova-status
	$(Q)# Link Placement binaries (since they were removed from RPMs)
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/placement-api /usr/bin/placement-api
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/placement-manage /usr/bin/placement-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/placement-status /usr/bin/placement-status
	$(Q)# Link the uWSGI binary for Placement WSGI
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/uwsgi /usr/bin/uwsgi

# Keep a privsep-helper in the antelope venv, and keep /usr/bin/privsep-helper pointed
# at it.
#
# oslo.privsep escalates by running `sudo privsep-helper`, resolved off sudo's
# secure_path (/sbin:/bin:/usr/sbin:/usr/bin), which never contains a venv's bin -- so
# the bare name has to exist there. One symlink covers every service that has not made
# the caracal hop: masakari and cyborg both reach the helper through
# /usr/bin/privsep-helper, and config_masakari.cpp and config_cyborg.cpp name that path
# in helper_command. two services used to be on that list and have since left it.
# neutron reached it a third way -- not through sudo's secure_path but through the
# exec_dirs in /etc/neutron/rootwrap.conf, since neutron agents escalate via
# `sudo neutron-rootwrap ... privsep-helper`; #628 took neutron to caracal and
# config_neutron.cpp now pins the caracal helper in all six of its privsep sections, so
# nothing under /etc/neutron resolves this symlink any more. #638 then took manila, and
# config_manila.cpp pins PRIVSEP_HELPER the same way.
#
# It is load-bearing rather than a convenience: with no /usr/bin/privsep-helper at all,
# an antelope agent that has not been pinned crash-loops on
# "FailedToDropPrivileges: privsep helper command exited non-zero (96)" -- which is how
# it was first found, as "Network NG [ neutron(3 metadata not all up) ]" before neutron
# had its own pins.
#
# So the helper is installed into *both* venvs from here: caracal's comes from the
# oslo.privsep named in the pip install above, which is the one nova itself escalates
# through (config_nova.cpp pins four helper_command values at
# /opt/openstack-caracal/bin/privsep-helper, since a python 3.10 helper cannot serve a
# caracal nova), and antelope's is installed here explicitly. Naming it rather than
# leaving it transitive is the same reasoning that names python3-designateclient in
# core/designate/designate.mk: a dependency nothing asks for is one that disappears
# silently -- and nova was the only component naming oslo.privsep in the antelope venv
# before this hop.
#
# Both halves go once the last antelope service reaches caracal: the pip install below,
# the symlink, and the helper_command pins in config_manila.cpp, config_masakari.cpp
# and config_cyborg.cpp. At that point the caracal half moves out of nova.mk too --
# every venv occupant will be naming its own helper by then.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			oslo.privsep"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/privsep-helper /usr/bin/privsep-helper

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/nova
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/nova

# generate default configurations and stage files
rootfs_install::
	$(Q)cp -f $(COREDIR)/nova/nova-dist.conf $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/nova.conf.sample $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/policy.yaml.sample $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/policy.json $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/release $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/placement-dist.conf $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/placement.conf.sample $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/placement-policy.yaml.sample $(ROOTDIR)/tmp/nova/
	$(Q)cp -f $(COREDIR)/nova/placement-policy.json $(ROOTDIR)/tmp/nova/
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
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/policy.yaml.sample /etc/nova/policy.yaml.sample
	$(Q)# api-paste.ini and rootwrap.conf are upstream data the nova wheel already puts
	$(Q)# under the venv prefix through its setup.cfg data_files, so core/nova no longer
	$(Q)# carries a second copy that only moves when someone remembers to re-copy it.
	$(Q)# Unlike glance's, nova's rootwrap.conf never narrowed exec_dirs -- it was the
	$(Q)# upstream default verbatim.
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 $(CARACAL_OPENSTACK_HOME_DIR)/etc/nova/api-paste.ini /etc/nova/api-paste.ini
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 $(CARACAL_OPENSTACK_HOME_DIR)/etc/nova/rootwrap.conf /etc/nova/rootwrap.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/policy.json /etc/nova/policy.json
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/nova/release /etc/nova/release
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/placement-dist.conf /usr/share/placement/placement-dist.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/placement.conf.sample /etc/placement/placement.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/placement-policy.yaml.sample /etc/placement/policy.yaml.sample
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/nova/placement-policy.json /etc/placement/policy.json
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
	$(Q)# also the wheel's, through the etc/nova/rootwrap.d/* glob in data_files
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 $(CARACAL_OPENSTACK_HOME_DIR)/etc/nova/rootwrap.d/compute.filters /usr/share/nova/rootwrap/compute.filters

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chown root:nova /usr/share/nova/nova-dist.conf
	$(Q)chroot $(ROOTDIR) chown root:nova /etc/nova/nova.conf
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

# Apply reviewable unified diffs (<rel>.py.patch beside pristine <rel>.py.orig,
# same convention as core/masakari/masakari.mk), then install brand-new
# downstream files (anything not *.patch/*.orig) verbatim. --forward keeps
# re-runs idempotent; a failed hunk aborts the build instead of shipping
# drift silently.
rootfs_install::
	$(Q)set -e; for p in $$(find $(NOVA_PATCHDIR) -name '*.py.patch' 2>/dev/null | sort); do \
		rel=$${p#$(NOVA_PATCHDIR)/}; tgt=$(NOVA_SRCDIR)/$${rel%.patch}; \
		echo "  PATCH $${rel%.patch}"; \
		patch --forward --no-backup-if-mismatch -r - "$$tgt" < "$$p" \
			|| { echo "nova: failed to apply $$p to $$tgt" >&2; exit 1; }; \
	done
	$(Q)cd $(NOVA_PATCHDIR) && find . -type f ! -name '*.patch' ! -name '*.orig' \
		! -name '*.pyc' ! -path '*/__pycache__/*' | \
		while read f; do install -D -m 644 "$$f" $(NOVA_SRCDIR)/"$$f"; done

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/nova/nova.d
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
	$(Q)chroot $(ROOTDIR) mkdir -p /var/lib/nova/instances
	$(Q)chroot $(ROOTDIR) chown nova:nova /var/lib/nova/instances

rootfs_install::
	$(Q)cp -f $(COREDIR)/nova/placement-uwsgi.ini $(ROOTDIR)/etc/placement/placement-uwsgi.ini
	$(Q)chroot $(ROOTDIR) chown root:placement /etc/placement/placement-uwsgi.ini
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/placement/placement-uwsgi.ini
	$(Q)cp -f $(COREDIR)/nova/openstack-placement-api.service $(ROOTDIR)/usr/lib/systemd/system/openstack-placement-api.service
	$(Q)chroot $(ROOTDIR) chmod 0644 /usr/lib/systemd/system/openstack-placement-api.service
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/placement
	$(Q)chroot $(ROOTDIR) chown placement:apache /var/lib/placement
	$(Q)chroot $(ROOTDIR) chmod 770 /var/lib/placement
