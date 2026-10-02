# Cube SDK
# cinder installation

ROOTFS_DNF += qemu-img cryptsetup lvm2 iscsi-initiator-utils device-mapper-multipath sudo sshpass
ROOTFS_DNF_NOARCH += nvmetcli targetcli

CINDER_SRCDIR := $(ROOTDIR)/opt/openstack-antelope/lib/python3.10/site-packages/cinder
CINDER_PATCHDIR := $(COREDIR)/cinder/$(OPENSTACK_RELEASE)_patch

CINDER_CONFDIR := $(ROOTDIR)/etc/cinder

# install cinder inside the python 3.10 virtual environment
# purestorage: support Pure Storage
# pywbem: support Fujitsu Eternus DX
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			cinder==22.3.0 \
			python-cinderclient \
			python-keystoneclient \
			uwsgi \
			etcd3gw \
			websocket-client \
			purestorage \
			pywbem"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder /usr/bin/cinder
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-3 /usr/bin/cinder-3
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-api /usr/bin/cinder-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-backup /usr/bin/cinder-backup
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-manage /usr/bin/cinder-manage
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-rootwrap /usr/bin/cinder-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-rtstool /usr/bin/cinder-rtstool
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-scheduler /usr/bin/cinder-scheduler
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-status /usr/bin/cinder-status
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-volume /usr/bin/cinder-volume
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-volume-usage-audit /usr/bin/cinder-volume-usage-audit
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/cinder-wsgi /usr/bin/cinder-wsgi

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
	$(Q)cp -f $(COREDIR)/cinder/api-paste.ini $(ROOTDIR)/tmp/cinder/
	$(Q)cp -f $(COREDIR)/cinder/rootwrap.conf $(ROOTDIR)/tmp/cinder/
	$(Q)cp -f $(COREDIR)/cinder/resource_filters.json $(ROOTDIR)/tmp/cinder/
	$(Q)cp -f $(COREDIR)/cinder/cinder-sudoers $(ROOTDIR)/tmp/cinder/
	$(Q)cp -f $(COREDIR)/cinder/volume.filters $(ROOTDIR)/tmp/cinder/
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
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/cinder/api-paste.ini /etc/cinder/api-paste.ini
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/cinder/rootwrap.conf /etc/cinder/rootwrap.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/cinder/resource_filters.json /etc/cinder/resource_filters.json
	$(Q)# install security configurations
	$(Q)chroot $(ROOTDIR) install -p -D -m 440 /tmp/cinder/cinder-sudoers /etc/sudoers.d/cinder
	$(Q)# install systemd unit files
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/cinder/openstack-cinder-api.service /usr/lib/systemd/system/openstack-cinder-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/cinder/openstack-cinder-scheduler.service /usr/lib/systemd/system/openstack-cinder-scheduler.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/cinder/openstack-cinder-volume.service /usr/lib/systemd/system/openstack-cinder-volume.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/cinder/openstack-cinder-backup.service /usr/lib/systemd/system/openstack-cinder-backup.service
	$(Q)# install rootwrap filters into system cinder deployment configuration
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/cinder/volume.filters /etc/cinder/rootwrap.d/

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
#
# Each carried file sits beside the upstream 22.3.0 file it was made from (*.orig), so
# `diff x.orig x` is the whole local change. A file carried as <rel>.py.patch is applied
# to the installed file instead; a whole file is copied over it:
# volume/drivers/nfs.py: NfsDriver.manage_existing and manage_existing_get_size, which
#   upstream still does not provide; the nfs.py half of upstream 0480073b9 (bug
#   1989514, below): an extend resizes the active file, which a snapshot made a qcow2
#   overlay, instead of the base file; and upstream d961d3c88 + c68475a3d (bug 2073146,
#   28.0.0, not backported to 2023.1; their remotefs.py and image_utils.py halves are
#   in those .patch files): initialize_connection reads the volume's format from its
#   admin metadata instead of guessing it from the file, and refuses only a virtual size
#   larger than the cinder size. A Glance image stored on NFS is a raw volume holding
#   the image's own bytes, so a qcow2 image was taken for a qcow2 volume of the image's
#   virtual size and every read-attach was refused (#1217)
# volume/drivers/remotefs.py.patch, image/image_utils.py.patch: two upstream fixes
#   that bug 2073146's fix stands on, since it reads the format from the volume's admin
#   metadata. 0480073b9 (bug 1989514; 23.4.0 and 24.3.0, never backported to 2023.1):
#   an online snapshot of an attached volume made a qcow2 overlay the active file but
#   left the format, and the attachment's connection_info, at raw, so the instance could
#   not boot after a stop/start; the patch records qcow2 in both. 8c03308ed (28.0.0):
#   an offline snapshot left the format at raw the same way, so an extend ran qemu-img
#   resize -f raw on the overlay; the patch keeps format (and the new base_format) in
#   step with the active file on every snapshot create and delete. One context line,
#   which 22.3.0 spells del(snap_info[...]), was resolved by hand, and d961d3c88's
#   image_utils.py keeps 22.3.0's noqa on its typing import; nothing else differs from
#   upstream. 8c03308ed's quobyte.py half is not carried: CubeCOS does not use the
#   Quobyte driver
rootfs_install::
	$(Q)set -e; for p in $$(find $(CINDER_PATCHDIR) -name '*.py.patch' 2>/dev/null | sort); do \
		rel=$${p#$(CINDER_PATCHDIR)/}; tgt=$(CINDER_SRCDIR)/$${rel%.patch}; \
		echo "  PATCH $${rel%.patch}"; \
		patch --forward --no-backup-if-mismatch -r - "$$tgt" < "$$p" \
			|| { echo "cinder: failed to apply $$p to $$tgt" >&2; exit 1; }; \
	done
	$(Q)[ ! -d $(CINDER_PATCHDIR) ] || { cd $(CINDER_PATCHDIR) && find . -type f ! -name '*.patch' ! -name '*.orig' \
		! -name '*.pyc' ! -path '*/__pycache__/*' | \
		while read f; do install -D -m 644 "$$f" $(CINDER_SRCDIR)/"$$f"; done; }

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
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/cinder
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/cinder/models
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/cinder/storage_extra_configs_ownership
