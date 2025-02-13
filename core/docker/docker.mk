# Cube SDK
# Docker installation

DOCKER_DIR := /opt/docker/

ROOTFS_DNF += containerd.io docker-ce docker-ce-cli docker-ce-rootless-extras skopeo

DOCKER_REPO = $(shell chroot $(ROOTDIR) dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo ; echo "docker")

rootfs_install::
	$(Q)chroot $(ROOTDIR) systemctl disable docker
	$(Q)chroot $(ROOTDIR) mkdir -p $(DOCKER_DIR)
	$(Q)cp -rf $(TOP_BLDDIR)/core/docker/registry/ $(ROOTDIR)/$(DOCKER_DIR)
	$(Q)cp -f $(TOP_BLDDIR)/core/docker/registry@2.tar $(ROOTDIR)/$(DOCKER_DIR)
