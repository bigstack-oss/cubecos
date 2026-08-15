# Cube SDK
# keycloak installation

# keycloak directories
KEYCLOAK_DIR := /opt/keycloak
KEYCLOAK_CONF_DIR := /etc/keycloak

# the bundled registry (core/docker/registry, copied into the rootfs) must
# hold the keycloak image tag pinned in chart-values.yaml; a missing or
# drifted tag means every fresh install ImagePullBackOffs -- fail the build.
rootfs_install::
	$(Q)charttag=$$(awk '/^  tag:/ {print $$2; exit}' $(COREDIR)/keycloak/chart-values.yaml); \
	tagsdir=$(TOP_BLDDIR)/core/docker/registry/docker/registry/v2/repositories/bigstack/keycloak/_manifests/tags; \
	if [ ! -d "$$tagsdir/$$charttag" ]; then \
		echo "keycloak: bundled registry lacks bigstack/keycloak:$$charttag (has: $$(ls $$tagsdir 2>/dev/null | tr '\n' ' ')) -- fresh installs would ImagePullBackOff" >&2; \
		exit 1; \
	fi

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(KEYCLOAK_DIR)
	$(Q)cp -f $(COREDIR)/keycloak/chart-values.yaml $(ROOTDIR)/$(KEYCLOAK_DIR)/
	$(Q)cp -f $(TOP_BLDDIR)/core/keycloak/keycloakx-*.tgz $(ROOTDIR)/$(KEYCLOAK_DIR)/
	$(Q)chroot $(ROOTDIR) mkdir -p $(KEYCLOAK_DIR)/db
	$(Q)cp -f $(COREDIR)/keycloak/db/* $(ROOTDIR)/$(KEYCLOAK_DIR)/db/
	$(Q)chroot $(ROOTDIR) mkdir -p $(KEYCLOAK_CONF_DIR)
