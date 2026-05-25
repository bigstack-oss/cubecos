# CUBE SDK

rootfs_install::
	$(Q)cp -f $(TOP_BLDDIR)/core/terraform/terraform-core/terraform-core $(ROOTDIR)/usr/local/bin/terraform
	$(Q)cp -f $(COREDIR)/terraform/scripts/* $(ROOTDIR)/usr/local/bin/
	$(Q)cp -rf $(TOP_BLDDIR)/core/terraform/terraform/ $(ROOTDIR)/var/lib/
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/terraform/values
	$(Q)cp -f $(COREDIR)/terraform/values/* $(ROOTDIR)/etc/cube/cos/terraform/values/
	$(Q)# patch terraform providers for CVEs
	$(Q)chroot $(ROOTDIR) mkdir -p /var/lib/terraform/patched-registry
	$(Q)chroot $(ROOTDIR) rsync -avz --progress /var/lib/terraform/.terraform/providers/ /var/lib/terraform/patched-registry/
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/terraform/configs
	$(Q)cp -f $(COREDIR)/terraform/override.tfrc $(ROOTDIR)/etc/cube/cos/terraform/configs/
	$(Q)chroot $(ROOTDIR) cp -f /etc/cube/cos/terraform/configs/override.tfrc /root/.terraformrc
	$(Q)chroot $(ROOTDIR) rm -f /var/lib/terraform/.terraform.lock.hcl
