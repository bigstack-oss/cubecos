# CUBE SDK

include ../../build.mk

include $(SRCDIR)/docker.mk

REGISTRY_TAR := registry@2.tar

$(REGISTRY_TAR):
	$(Q)skopeo copy docker://registry:2 docker-archive:$(REGISTRY_TAR):registry:2 >/dev/null

registry: $(REGISTRY_TAR) ../keycloak/.load-img
	$(Q)make build-image -C ../k3s
	$(call RUN_CMD_TIMED, make run-registry,"  RUN     docker registry")
	$(Q)make copy-image -C ../k3s
	$(call RUN_CMD_TIMED, \
		sh -x $(TOP_SRCDIR)/core/keycloak/copy-images.sh containers-storage:$(shell cat ../keycloak/.load-img), \
		"  COPY    keycloak image")
	$(Q)make copy-image -C ../rancher FULL=$(FULL)
	$(Q)make copy-image -C ../nvidia
	$(Q)make rm-registry

k8s-full-registry.tar:
	$(Q)make registry FULL=true
	$(Q)tar -cvf $@ ./registry/

.PHONY: run-registry
run-registry: $(REGISTRY_TAR)
	$(Q)mkdir -p ./registry
	$(Q)podman rm -ivf registry >/dev/null || true
	$(Q)podman load -q -i $(REGISTRY_TAR) && \
		podman run -q -d --name=registry -v ./registry/:/var/lib/registry/ -p 5080:5000 docker.io/library/registry:2

.PHONY: rm-registry
rm-registry:
	$(Q)podman rm -ivf registry >/dev/null

.PHONY .IGNORE: push-image
push-image:
	$(call RUN_CMD_TIMED, make run-registry,"  RUN     docker registry")
	$(call RUN_CMD_TIMED, \
		podman push $(IMG) --tls-verify=false \
		,"  PUSH    $(IMG)")
	$(Q)make rm-registry

.PHONY .IGNORE: copy-image
copy-image:
	$(call RUN_CMD_TIMED, make run-registry,"  RUN     docker registry")
	$(call RUN_CMD_TIMED, \
		skopeo copy --all --dest-tls-verify=false --preserve-digests \
			docker://$(IMG) docker://$(shell echo $(IMG) | sed -E 's/^[^\/]+\//localhost:5080\//') \
		,"  COPY    $(IMG)")
	$(Q)make rm-registry

install:: registry $(REGISTRY_TAR)
	$(Q)mkdir -p $(DOCKER_DIR)
	$(Q)cp -rf $^ $(DOCKER_DIR)

test:: install
	$(Q)podman container inspect registry >/dev/null || podman run -d --name=registry -p 5080:5000 -v $(DOCKER_DIR)/registry/:/var/lib/registry/ docker.io/library/registry:2

testclean:: rm-registry

clean:: testclean
	$(Q)rm -rf $(DOCKER_DIR)

BUILD += registry registry@2.tar
BUILDCLEAN += registry registry@2.tar
DISTCLEAN += k8s-full-registry.tar

include $(HEX_MAKEDIR)/hex_sdk.mk
