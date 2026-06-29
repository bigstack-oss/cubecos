# Cube SDK
# glance installation

ROOTFS_DNF += qemu-img

# install glance
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			glance==26.1.0 \
			os-brick \
			python-cinderclient \
			python-glanceclient \
			pyxattr \
			pysendfile"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/glance
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/glance

# generate default configs
rootfs_install::
	$(Q)cp -rf $(COREDIR)/glance/oslo-config-generator $(ROOTDIR)/tmp/glance/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		oslo-config-generator \
			--config-file=/tmp/glance/oslo-config-generator/glance-api.conf \
			--output-file=/tmp/glance/glance-api.conf.sample"
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		oslo-config-generator \
			--config-file=/tmp/glance/oslo-config-generator/glance-cache.conf \
			--output-file=/tmp/glance/glance-cache.conf.sample"
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		oslo-config-generator \
			--config-file=/tmp/glance/oslo-config-generator/glance-image-import.conf \
			--output-file=/tmp/glance/glance-image-import.conf.sample"
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		oslo-config-generator \
			--config-file=/tmp/glance/oslo-config-generator/glance-manage.conf \
			--output-file=/tmp/glance/glance-manage.conf.sample"
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		oslo-config-generator \
			--config-file=/tmp/glance/oslo-config-generator/glance-scrubber.conf \
			--output-file=/tmp/glance/glance-scrubber.conf.sample"
	$(Q)cp -f $(COREDIR)/glance/glance-api-paste.ini $(ROOTDIR)/tmp/glance/
	$(Q)cp -f $(COREDIR)/glance/glance-swift.conf $(ROOTDIR)/tmp/glance/
	$(Q)cp -f $(COREDIR)/glance/glance-rootwrap.conf $(ROOTDIR)/tmp/glance/
	$(Q)cp -f $(COREDIR)/glance/schema-image.json $(ROOTDIR)/tmp/glance/
	$(Q)cp -rf $(COREDIR)/glance/metadefs $(ROOTDIR)/tmp/glance/
	$(Q)cp -f $(COREDIR)/glance/openstack-glance-api.service $(ROOTDIR)/tmp/glance/
	$(Q)cp -f $(COREDIR)/glance/openstack-glance-scrubber.service $(ROOTDIR)/tmp/glance/
	$(Q)cp -f $(COREDIR)/glance/openstack-glance.logrotate $(ROOTDIR)/tmp/glance/
	$(Q)cp -f $(COREDIR)/glance/glance-sudoers $(ROOTDIR)/tmp/glance/
	$(Q)cp -f $(COREDIR)/glance/glance_cinder_store.filters $(ROOTDIR)/tmp/glance/
	$(Q)cp -f $(COREDIR)/glance/os-brick.filters $(ROOTDIR)/tmp/glance/

# install system directories and files
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 /usr/share/glance
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/glance/images
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/glance/metadefs
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/glance/glance-api.conf.sample /etc/glance/glance-api.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/glance/glance-api-paste.ini /etc/glance/glance-api-paste.ini
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/glance/glance-cache.conf.sample /etc/glance/glance-cache.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/glance/glance-scrubber.conf.sample /etc/glance/glance-scrubber.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/glance/glance-swift.conf /etc/glance/glance-swift.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/glance/glance-image-import.conf.sample /etc/glance/glance-image-import.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/glance/glance-rootwrap.conf /etc/glance/rootwrap.conf
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/glance/schema-image.json /etc/glance/schema-image.json
	$(Q)chroot $(ROOTDIR) bash -c "install -p -D -m 640 /tmp/glance/metadefs/*.json /etc/glance/metadefs/"
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/glance/openstack-glance-api.service /usr/lib/systemd/system/openstack-glance-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/glance/openstack-glance-scrubber.service /usr/lib/systemd/system/openstack-glance-scrubber.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/glance/openstack-glance.logrotate /etc/logrotate.d/openstack-glance
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/run/glance
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/log/glance
	$(Q)chroot $(ROOTDIR) install -p -D -m 440 /tmp/glance/glance-sudoers /etc/sudoers.d/glance
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/glance/rootwrap.d
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/glance/glance_cinder_store.filters /etc/glance/rootwrap.d
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/glance/os-brick.filters /etc/glance/rootwrap.d

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chown root:glance /etc/glance/glance-api.conf
	$(Q)chroot $(ROOTDIR) chown root:glance /etc/glance/glance-api-paste.ini
	$(Q)chroot $(ROOTDIR) chown root:glance /etc/glance/glance-cache.conf
	$(Q)chroot $(ROOTDIR) chown root:glance /etc/glance/glance-scrubber.conf
	$(Q)chroot $(ROOTDIR) chown root:glance /etc/glance/glance-swift.conf
	$(Q)chroot $(ROOTDIR) chown root:glance /etc/glance/glance-image-import.conf
	$(Q)chroot $(ROOTDIR) chown root:glance /etc/glance/rootwrap.conf
	$(Q)chroot $(ROOTDIR) chown root:glance /etc/glance/schema-image.json
	$(Q)chroot $(ROOTDIR) bash -c "chown root:glance /etc/glance/metadefs/*.json"
	$(Q)chroot $(ROOTDIR) chown root:glance /etc/logrotate.d/openstack-glance
	$(Q)chroot $(ROOTDIR) chown root:root /etc/glance/rootwrap.d/glance_cinder_store.filters
	$(Q)chroot $(ROOTDIR) chown root:root /etc/glance/rootwrap.d/os-brick.filters
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/lib/glance
	$(Q)chroot $(ROOTDIR) chown glance:nobody /var/lib/glance
	$(Q)chroot $(ROOTDIR) chmod 0750 /var/log/glance
	$(Q)chroot $(ROOTDIR) chown glance:glance /var/log/glance

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/glance

# install custom files
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p /var/lib/glance/mnt
	$(Q)chroot $(ROOTDIR) mkdir -p /var/lib/glance/locks
	$(Q)chroot $(ROOTDIR) mkdir -p /var/lib/glance/image-cache
	$(Q)chroot $(ROOTDIR) chown -R glance:glance /var/lib/glance
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/glance/cirros-0.4.0-x86_64-disk.qcow2 ./etc/glance
	$(Q)cp -f $(ROOTDIR)/etc/glance/glance-api.conf $(ROOTDIR)/etc/glance/glance-api.conf.org
	$(Q)touch $(ROOTDIR)/etc/glance/glance-api.conf.def
	$(Q)cp -f $(COREDIR)/glance/policy.yaml $(ROOTDIR)/etc/glance/
	$(Q)chroot $(ROOTDIR) chown glance:glance /etc/glance/policy.yaml
