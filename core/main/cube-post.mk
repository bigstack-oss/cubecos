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

rootfs_install::
	$(Q)rm -f $(ROOTDIR)/*.tsv $(LOCKED_RPMS) $(BLKLST_RPMS)
	$(Q)chroot $(ROOTDIR) bash -c "rm -rf /usr/local/share/{doc,man} /usr/share/{man,doc,licenses} /usr/src /usr/local/src /var/log/*.log /var/cache/dnf/* /{tmp,boot}/* /lib/.build-id" /afs
	$(Q)chroot $(ROOTDIR) find /usr -type f -name '*.pyc' -exec rm {} \;

rootfs_install::
	$(call RUN_CMD_TIMED, cd $(ROOTDIR) && syft --config $(SRCDIR)/syft.yml --source-version $(PROJ_NAME)_$(PROJ_VERSION) ./,"  GEN     sbom")
	$(call RUN_CMD_TIMED, mv $(ROOTDIR)/syft-fs-cubecos.cdx.json $(PROJ_SHIPDIR)/$(PROJ_SBM) ; rm -f $(ROOTDIR)/syft*,"  COPY    sbom")

	$(call RUN_CMD_TIMED, grype sbom:$(PROJ_SHIPDIR)/$(PROJ_SBM) --output=json > $(PROJ_SHIPDIR)/$(PROJ_VLN),"  SCAN    vulnerabilities")
	$(call RUN_CMD_TIMED, COSIGN_PASSWORD= cosign sign-blob --key cosign.key --bundle=$(PROJ_SHIPDIR)/$(PROJ_BDL) $(PROJ_SHIPDIR)/$(PROJ_SBM),"  GEN      bundle")
	$(call RUN_CMD_TIMED, COSIGN_PASSWORD= cosign sign-blob --key cosign.key --bundle=$(PROJ_SHIPDIR)/$(PROJ_BDL) $(PROJ_SHIPDIR)/$(PROJ_SBM),"  CHK      sbom")
