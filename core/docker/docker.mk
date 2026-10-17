# Cube SDK
# Docker installation

DOCKER_DIR := /opt/docker

ROOTFS_DNF += containerd.io docker-ce docker-ce-cli docker-ce-rootless-extras skopeo

heavy_components_install::
	$(Q)chroot $(ROOTDIR) systemctl disable docker
	$(Q)chroot $(ROOTDIR) mkdir -p $(DOCKER_DIR)
	$(Q)cp -rf $(TOP_BLDDIR)/core/docker/registry/ $(ROOTDIR)/$(DOCKER_DIR)/
	$(Q)cp -f $(TOP_BLDDIR)/core/docker/registry@2.tar $(ROOTDIR)/$(DOCKER_DIR)/

# for RC builds
heavyfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf $(DOCKER_DIR)/registry
	$(Q)chroot $(ROOTDIR) rm -rf $(DOCKER_DIR)/registry@2.tar
	$(Q)cp -rf $(TOP_BLDDIR)/core/docker/registry/ $(ROOTDIR)/$(DOCKER_DIR)/
	$(Q)cp -f $(TOP_BLDDIR)/core/docker/registry@2.tar $(ROOTDIR)/$(DOCKER_DIR)/
