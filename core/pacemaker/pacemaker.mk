# Cube SDK
# pacemaker installation

# pacemaker-2.1.8-1.el9 fails to start with info: Connection to CIB manager for crmd failed: Transport endpoint is not connnected
PACEMAKER_VER := 2.1.7-5.el9
PACEMAKER_DNF := pacemaker-$(PACEMAKER_VER) pacemaker-remote-$(PACEMAKER_VER) pacemaker-cli-$(PACEMAKER_VER) pacemaker-cluster-libs-$(PACEMAKER_VER) pacemaker-libs-$(PACEMAKER_VER)
LOCKED_DNF += $(PACEMAKER_DNF) pacemaker-schemas-$(PACEMAKER_VER)
ROOTFS_DNF_NOARCH += pacemaker-schemas-$(PACEMAKER_VER)
ROOTFS_DNF += $(PACEMAKER_DNF) pcs fence-agents-all libqb

rootfs_install::
	$(Q)chroot $(ROOTDIR) systemctl disable rpcbind nfs-convert || true
