# CUBE SDK

include ../../build.mk
include $(SRCDIR)/rancher.mk

APP_VERSION := 2.11.2
CLI_VERSION := 2.11.2

IMG_LIST := $(shell cat $(SRCDIR)/images.txt)
ifeq ($(FULL),true)
	IMG_LIST += $(shell cat $(SRCDIR)/rancher-images.txt)
endif

CLI_BIN := rancher
CHART := rancher-$(APP_VERSION).tgz


$(CLI_BIN):
	$(Q)wget -qO- --no-check-certificate https://releases.rancher.com/cli2/v$(CLI_VERSION)/rancher-linux-amd64-v$(CLI_VERSION).tar.gz | tar -zx --strip-components=2

$(CHART):
	$(Q)helm repo add rancher-stable https://releases.rancher.com/server-charts/stable $(QEND)
	$(Q)helm pull rancher-stable/rancher --version $(APP_VERSION) $(QEND)

nodedrivers/docker-machine-driver-cube:
	$(Q)mkdir -p nodedrivers/
	$(call RUN_CMD_TIMED,(cd $(SRCDIR)/rancher-machine-driver-cube/ && CGO_ENABLED=0 go build -o $(BLDDIR)/$@ && go mod tidy),"  GEN     $@")

.PHONY: build-image
build-image:
	$(call RUN_CMD_TIMED, \
		podman image inspect localhost/bigstack/rancher:v$(APP_VERSION) >/dev/null || SRCDIR=$(SRCDIR) sh -x $(SRCDIR)/build/buildah-image.sh v$(APP_VERSION) \
		,"  BUILD   rancher image")

.PHONY: copy-image
copy-image:
	$(call RUN_CMD_TIMED, \
		sh -x $(TOP_SRCDIR)/core/docker/copy-images.sh $(IMG_LIST); \
		for dir in $(SUBDIRS); do make copy-image -C $$dir/; done; \
		,"  COPY    rancher image")

install: $(CLI_BIN) $(CHART)
	$(Q)cp -f $(CLI_BIN) /usr/local/bin/
	$(Q)mkdir -p $(RANCHER_DIR)
	$(Q)cp -f $(CHART) $(SRCDIR)/chart-values.yaml $(RANCHER_DIR)

test:: install
ifeq ($(DEP),1)
	$(Q)make test -C ../k3s
endif
	- $(Q)k3s kubectl create ns cattle-system
	- $(Q)k3s kubectl create secret generic tls-ca -n cattle-system --from-file=cacerts.pem=/var/www/certs/server.cert
	$(Q)helm --kubeconfig /etc/rancher/k3s/k3s.yaml upgrade --install rancher $(RANCHER_DIR)/$(CHART) \
		-n cattle-system --create-namespace --wait --wait-for-jobs -f $(RANCHER_DIR)/chart-values.yaml

testclean::
	$(Q)helm --kubeconfig /etc/rancher/k3s/k3s.yaml uninstall rancher -n cattle-system || true
ifeq ($(DEP),1)
	$(Q)make testclean -C ../k3s
endif

clean:: testclean
	$(Q)rm -f /usr/local/bin/$(CLI_BIN)
	$(Q)podman image rm -f localhost/bigstack/rancher:v$(APP_VERSION) 2>/dev/null || true

BUILD += $(CLI_BIN) $(CHART) nodedrivers/docker-machine-driver-cube
BUILDCLEAN += $(CLI_BIN) $(CHART) nodedrivers $(RANCHER_DIR)

SUBDIRS += cpo

include $(HEX_MAKEDIR)/hex_sdk.mk
