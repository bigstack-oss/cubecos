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
	$(Q)chroot $(ROOTDIR) bash -c "dnf autoremove -y systemtap-runtime"
	$(Q)sed -i -e "/stapunpriv/d" -e "/stapusr/d" -e "/stapsys/d" -e "/stapdev/d" $(ROOTDIR)/etc/passwd $(ROOTDIR)/etc/shadow $(ROOTDIR)/etc/group $(ROOTDIR)/etc/gshadow

rootfs_install::
	$(Q)diff $(ROOTDIR)/etc/passwd $(BLDDIR)/passwd.before
	$(Q)diff $(ROOTDIR)/etc/shadow $(BLDDIR)/shadow.before
	$(Q)diff $(ROOTDIR)/etc/group $(BLDDIR)/group.before
	$(Q)diff $(ROOTDIR)/etc/gshadow $(BLDDIR)/gshadow.before

# Guard: no build-network-only endpoint may ship in the image.
#
# The image carries its own package sources -- ~25 .repo files under /etc/yum.repos.d, none of
# which anything in this tree removes before mountrootfs packs $(ROOTDIR) -- and customers resolve
# against them at runtime (`hex_sdk` drives `dnf update --advisory=` / `--cve=`). So a build that
# redirects any of those at an internal mirror would ship that hostname to every installed node,
# and it would not be noticed until an air-gapped customer's update failed. The only precedents
# for build-time-only network config are the resolv.conf copy/remove idiom and
# RootfsEnableProxy/RootfsDisableProxy (hex/scripts/functions), both of which undo themselves;
# this is the check that keeps it that way.
#
# Two classes are rejected: RFC1918 literals (which no public upstream ever uses), and whatever
# hosts the caller names in MIRROR_LEAK_HOSTS -- CI sets that to its mirror, so the guard needs no
# allowlist of public upstreams and cannot fail spuriously on a legitimate new one. 127.0.0.0/8 is
# deliberately not rejected: /opt/k3s/registries.yaml mirrors to localhost:5080 on purpose.
#
# The address has to sit on an endpoint-bearing key rather than anywhere in the file. /root/.gitconfig
# is the reason: config_* writes `email = <host>@<mgmt-ip>` there at first boot, so matching the bare
# address would fail every build on a node identity that has nothing to do with package sources.
MIRROR_LEAK_HOSTS ?=
MIRROR_LEAK_KEYS := (baseurl|metalink|mirrorlist|gpgkey|proxy|index-url|extra-index-url|trusted-host|registry|location|mirror|insteadOf)
SHIPPED_NET_CFG := etc/yum.repos.d etc/dnf/dnf.conf etc/pip.conf etc/gitconfig root/.gitconfig \
                   etc/containers etc/npmrc root/.npmrc etc/wgetrc root/.wgetrc root/.curlrc root/.pip

rootfs_install::
	$(Q)hosts='10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+' ; \
	for h in $(MIRROR_LEAK_HOSTS) ; do hosts="$$hosts|$$h" ; done ; \
	pats='$(MIRROR_LEAK_KEYS)[[:space:]]*=.*('"$$hosts"')' ; \
	rc=0 ; \
	for p in $(SHIPPED_NET_CFG) ; do \
		[ -e $(ROOTDIR)/$$p ] || continue ; \
		if grep -RInE "$$pats" $(ROOTDIR)/$$p 2>/dev/null ; then rc=1 ; fi ; \
	done ; \
	if [ $$rc -ne 0 ] ; then \
		echo "ERROR: the lines above are build-network-only endpoints that would ship in the image." >&2 ; \
		echo "Redirect build-time only (see RootfsEnableProxy/RootfsDisableProxy), or drop it before packing." >&2 ; \
		exit 1 ; \
	fi

rootfs_install::
	$(Q)rm -f $(ROOTDIR)/*.tsv $(LOCKED_RPMS)
	$(Q)for r in $$(cat rootfs/removed_rpms.txt) ; do chroot rootfs rpm -e --nodeps $${r%.el9.*} 2>/dev/null || true; done
	$(Q)chroot $(ROOTDIR) bash -c "rm -rf /usr/local/share/{doc,man} /usr/share/{man,doc,licenses} /usr/src /usr/local/src /var/log/*.log /var/cache/dnf/* /{tmp,boot}/* /lib/.build-id" /afs
	$(Q)chroot $(ROOTDIR) find /usr -type f -name '*.pyc' -exec rm {} \;
