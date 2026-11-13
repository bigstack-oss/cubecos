# Cube SDK
# pacemaker installation

# pacemaker-2.1.8-1.el9 fails to start with info: Connection to CIB manager for crmd failed: Transport endpoint is not connnected
PACEMAKER_VER := 2.1.11-1.el9
PACEMAKER_DNF := pacemaker-$(PACEMAKER_VER) pacemaker-remote-$(PACEMAKER_VER) pacemaker-cli-$(PACEMAKER_VER) pacemaker-cluster-libs-$(PACEMAKER_VER) pacemaker-libs-$(PACEMAKER_VER)
LOCKED_DNF += $(PACEMAKER_DNF) pacemaker-schemas-$(PACEMAKER_VER)
ROOTFS_DNF_NOARCH += pacemaker-schemas-$(PACEMAKER_VER)
ROOTFS_DNF += $(PACEMAKER_DNF) pcs libqb
# No fence agents: STONITH is disabled on every cluster (proj_functions, config_pacemaker.cpp and the
# health repair all set stonith-enabled=false), no stonith resource is ever created, and nothing
# runs a fence_* agent -- masakari's host monitor calls ipmitool directly. fence-agents-all brought
# in 35 fence-agents-* rpms and fence-virt, several of them with known vulnerabilities, for nothing;
# pcs and pacemaker neither require nor recommend them. The blocklist keeps a cached copy from
# installing anyway. pcs stonith list and the pcsd UI's fence-device pages show no agents.
BLKLST_DNF += fence-agents fence-virt

rootfs_install::
	$(Q)chroot $(ROOTDIR) systemctl disable rpcbind nfs-convert || true
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/pacemaker/vaw.service ./lib/systemd/system
	$(Q)$(INSTALL_SCRIPT) -f $(ROOTDIR) $(COREDIR)/pacemaker/vaw ./usr/sbin/vaw
