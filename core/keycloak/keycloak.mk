# Cube SDK
# keycloak installation
KEYCLOAK_DIR := /opt/keycloak/

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(KEYCLOAK_DIR)
	$(Q)cp -f $(COREDIR)/keycloak/chart-values.yaml $(ROOTDIR)/$(KEYCLOAK_DIR)
	$(Q)cp -f $(TOP_BLDDIR)/core/keycloak/keycloak-*.tgz $(ROOTDIR)/$(KEYCLOAK_DIR)
