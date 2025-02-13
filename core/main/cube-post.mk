# Cube SDK
# post actions performed after the installation openstack packages

LICENSE_KEY := $(HEX_BLDDIR)/hex_sdk_library/license/license_key.h

# sanity check
rootfs_install::
	$(Q)for b in $(PROJ_GUARDED_BIN); \
	do \
	B=`basename $$b | tr '[:lower:]' '[:upper:]'` ; \
	[ "$$(cat $(LICENSE_KEY) | grep $${B}_CHECKSUM | awk -F'"' '{print $$2}')" = "$$(sha256sum $(ROOTDIR)/$$b | cut -d' ' -f1)" ] ; \
	done

# final cleanup
rootfs_install::
	$(Q)chroot $(ROOTDIR) sh -c "find /etc/logrotate.d -name '*' -type f | xargs sed -i -e '/\srotate/d'"
	$(Q)chroot $(ROOTDIR) sh -c "find /etc/logrotate.d -name '*' -type f | xargs sed -i -e '/\shourly/d'"
	$(Q)chroot $(ROOTDIR) sh -c "find /etc/logrotate.d -name '*' -type f | xargs sed -i -e '/\sweekly/d'"
	$(Q)chroot $(ROOTDIR) sh -c "find /etc/logrotate.d -name '*' -type f | xargs sed -i -e '/\smonthly/d'"
#	$(Q)chroot $(ROOTDIR) /sbin/setfiles -F -e /proc -e /sys -e /dev /etc/selinux/targeted/contexts/files/file_contexts /
	$(Q)cp -f $(SRCDIR)/selinux.config $(ROOTDIR)/etc/selinux/config
	$(Q)chroot $(ROOTDIR) bash -c "dnf list installed | egrep \"devel|headers\" | grep -v python3-devel | awk '{print \$$1}'| xargs -i dnf autoremove -y {}"

rootfs_install::
	$(Q)diff $(ROOTDIR)/etc/passwd $(BLDDIR)/passwd.before
	$(Q)diff $(ROOTDIR)/etc/shadow $(BLDDIR)/shadow.before
	$(Q)diff $(ROOTDIR)/etc/group $(BLDDIR)/group.before
	$(Q)diff $(ROOTDIR)/etc/gshadow $(BLDDIR)/gshadow.before

rootfs_install::
	$(Q)rm -f $(ROOTDIR)/*.tsv $(LOCKED_RPMS) $(BLKLST_RPMS)
	$(Q)chroot $(ROOTDIR) bash -c "rm -rf /usr/local/share/{doc,man} /usr/share/{man,doc,licenses} /usr/src /usr/local/src /var/log/*.log /var/cache/dnf/* /{tmp,boot}/* /lib/.build-id" /afs
	$(Q)chroot $(ROOTDIR) find /usr -type f -name '*.pyc' -exec rm {} \;
