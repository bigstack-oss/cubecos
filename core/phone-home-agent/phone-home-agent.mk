# Cube SDK
# phone-home-agent installation into the node OS image.

PHONE_HOME_AGENT_PROG := phone-home-agent

$(call PROJ_INSTALL_PROGRAM,-S,$(TOP_BLDDIR)/core/phone-home-agent/$(PHONE_HOME_AGENT_PROG),./usr/local/bin)

rootfs_install::
	$(Q)chroot $(ROOTDIR) ln -sf /usr/local/bin/$(PHONE_HOME_AGENT_PROG) /usr/sbin/
	$(Q)mkdir -p $(ROOTDIR)/etc/cube
	$(Q)cp -f $(COREDIR)/phone-home-agent/$(PHONE_HOME_AGENT_PROG).service $(ROOTDIR)/usr/lib/systemd/system/
	$(Q)chroot $(ROOTDIR) systemctl enable $(PHONE_HOME_AGENT_PROG).service

# for RC builds
heavyfs_install::
	$(Q)chroot $(ROOTDIR) ln -sf /usr/local/bin/$(PHONE_HOME_AGENT_PROG) /usr/sbin/
	$(Q)mkdir -p $(ROOTDIR)/etc/cube
	$(Q)cp -f $(COREDIR)/phone-home-agent/$(PHONE_HOME_AGENT_PROG).service $(ROOTDIR)/usr/lib/systemd/system/
	$(Q)chroot $(ROOTDIR) systemctl enable $(PHONE_HOME_AGENT_PROG).service
