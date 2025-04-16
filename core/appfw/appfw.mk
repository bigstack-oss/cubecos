# Cube SDK
# appfw packages

ROOTFS_DNF_NOARCH += ansible
ROOTFS_PIP += git+https://opendev.org/x/ospurge.git
ROOTFS_PIP += git+https://github.com/rancher/client-python.git@master

rootfs_install::
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/resolv.conf
	$(Q)for i in {1..5}; do ! timeout 60 chroot $(ROOTDIR) ansible-galaxy collection install 'openstack.cloud:=1.8.0' --force || break ; done
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)mkdir -p $(ROOTDIR)/opt/appfw
	$(Q)cp -r $(TOP_SRCDIR)/core/appfw/{ansible,bin} $(ROOTDIR)/opt/appfw/
	$(Q)cp -r $(TOP_BLDDIR)/core/appfw/appfw.tgz $(ROOTDIR)/opt/appfw/

#	$(Q)mkdir -p $(ROOTDIR)/opt/appfw/charts/{chartmuseum,docker-registry,keycloak}
#	$(Q)cp $(TOP_SRCDIR)/core/appfw/charts/chartmuseum/*.yaml $(ROOTDIR)/opt/appfw/charts/chartmuseum/
#	$(Q)cp $(TOP_BLDDIR)/core/appfw/charts/chartmuseum/*.tgz $(ROOTDIR)/opt/appfw/charts/chartmuseum/
#	$(Q)cp $(TOP_SRCDIR)/core/appfw/charts/docker-registry/*.yaml $(ROOTDIR)/opt/appfw/charts/docker-registry/
#	$(Q)cp $(TOP_BLDDIR)/core/appfw/charts/docker-registry/*.tgz $(ROOTDIR)/opt/appfw/charts/docker-registry/
#	$(Q)cp $(TOP_SRCDIR)/core/appfw/charts/keycloak/keycloak-values.yaml $(ROOTDIR)/opt/appfw/charts/keycloak/
#	$(Q)cp $(TOP_BLDDIR)/core/appfw/charts/keycloak/*.tgz $(ROOTDIR)/opt/appfw/charts/keycloak/
