# CUBE SDK

include ../../build.mk
include $(SRCDIR)/keycloak.mk

APP_VERSION := 17.0.1-legacy
CHART_VERSION := 18.1.1
CHART := keycloak-$(CHART_VERSION).tgz
IMG_BUILD := localhost:5080/bigstack/keycloak:$(APP_VERSION)

$(CHART):
	$(Q)helm repo add codecentric https://codecentric.github.io/helm-charts $(QEND)
	$(Q)helm pull codecentric/keycloak --version $(CHART_VERSION)


.build-img:
	$(call RUN_CMD_TIMED, \
		SRCDIR=$(SRCDIR) sh -x $(SRCDIR)/build/buildah-image.sh $(APP_VERSION) \
		,"  BUILD   keycloak image")
	$(Q)touch $@

.push-img: .build-img
	$(Q)make push-image -C $(TOP_BLDDIR)/core/docker IMG=$(IMG_BUILD)
	$(Q)touch $@

.PHONY: copy-image
copy-image: .build-img
	$(call RUN_CMD_TIMED, \
		sh -x $(TOP_SRCDIR)/core/docker/copy-images.sh containers-storage:$(IMG_BUILD) \
		,"  COPY    keycloak image")

install:: $(CHART) .push-img
	$(Q)mkdir -p $(KEYCLOAK_DIR)
	$(Q)cp -f $(SRCDIR)/chart-values.yaml $(KEYCLOAK_DIR)
	$(Q)cp -f $(CHART) $(KEYCLOAK_DIR)

test:: install
ifeq ($(DEP),1)
	$(Q)make test -C $(TOP_BLDDIR)/core/k3s
endif
	$(Q)podman run -d -p 3306:3306 --name=mysql \
		-e MYSQL_ALLOW_EMPTY_PASSWORD=true \
		-e MYSQL_DATABASE=keycloak \
		-e MYSQL_USER=keycloak \
		-e MYSQL_PASSWORD=password \
		docker.io/library/mariadb:10.3.27
	$(Q)helm --kubeconfig /etc/rancher/k3s/k3s.yaml upgrade --install keycloak $(KEYCLOAK_DIR)/$(CHART) \
		-n keycloak --create-namespace --wait --wait-for-jobs -f $(KEYCLOAK_DIR)/chart-values.yaml

test-podman:: .build-img
	$(Q)podman run -d -p 80:8080 -p 443:8443 --name=keycloak \
		-e KEYCLOAK_USER=admin \
		-e KEYCLOAK_PASSWORD=admin \
		-e KEYCLOAK_DEFAULT_THEME=cube \
		$(IMG_BUILD)
	$(Q)echo Accessing keycloak on http://$(shell cat /etc/hosts | grep $$(cat /etc/hostname) | awk '{print $$1}')/auth/


testclean::
ifeq ($(DEP),1)
	$(Q)make testclean -C $(TOP_BLDDIR)/core/k3s
endif
	$(Q)helm --kubeconfig /etc/rancher/k3s/k3s.yaml uninstall keycloak -n keycloak 2>/dev/null || true
	$(Q)k3s kubectl delete ns keycloak 2>/dev/null || true
	$(Q)podman rm -if keycloak >/dev/null
	$(Q)podman rm -if mysql >/dev/null

clean:: testclean
	$(Q)podman image rm -f $(IMG_BUILD) 2>/dev/null || true

BUILD += $(CHART) .push-img
BUILDCLEAN += $(CHART) .build-img .push-img $(KEYCLOAK_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
