# CUBE SDK

include ../../build.mk
include $(SRCDIR)/rancher.mk

APP_VERSION := 2.11.16
CLI_VERSION := 2.11.16

CLI_REPO    := https://github.com/rancher/cli.git
CLI_SRC_DIR := rancher-cli-source

IMG_LIST := $(shell cat $(SRCDIR)/images.txt)
ifeq ($(FULL),true)
	IMG_LIST += $(shell cat $(SRCDIR)/rancher-images.txt)
endif

CLI_BIN := rancher
CHART   := rancher-$(APP_VERSION).tgz

$(CLI_SRC_DIR):
	$(call RUN_CMD_TIMED,git clone -b v$(CLI_VERSION) $(CLI_REPO) $(CLI_SRC_DIR),"  CLONE   rancher-cli")

$(CLI_BIN): $(CLI_SRC_DIR)
	$(call RUN_CMD_TIMED,cd $(CLI_SRC_DIR) && go mod tidy,"  UPDATE  rancher-cli")
	$(call RUN_CMD_TIMED,cd $(CLI_SRC_DIR) && \
		CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		go build \
		-ldflags="-s -w -X main.VERSION=v$(CLI_VERSION) -extldflags '-static'" \
		-o ../$(CLI_BIN) ., \
		"  BUILD   rancher-cli")

# One source build emits both the chart and the upstream server image; see
# build/build-from-source.sh for why neither is pulled prebuilt any more.
# The chart is the make-visible artifact, so it stands in for both.
$(CHART):
	$(call RUN_CMD_TIMED, \
		sh $(SRCDIR)/build/build-from-source.sh v$(APP_VERSION) $(CURDIR) \
		,"  BUILD   rancher server image + chart from source")

.PHONY: build-image
build-image: $(CHART)
	$(call RUN_CMD_TIMED, \
		podman image inspect localhost/bigstack/rancher:v$(APP_VERSION) >/dev/null || SRCDIR=$(SRCDIR) sh -x $(SRCDIR)/build/buildah-image.sh v$(APP_VERSION) \
		,"  BUILD   rancher image")

.PHONY: copy-image
copy-image:
	$(call RUN_CMD_TIMED, \
		sh -x $(COREDIR)/docker/copy-images.sh $(IMG_LIST); \
		for dir in $(SUBDIRS); do make copy-image -C $$dir/; done; \
		,"  COPY    rancher image")

install: $(CLI_BIN) $(CHART)
	$(Q)cp -f $(CLI_BIN) /usr/local/bin/
	$(Q)mkdir -p $(RANCHER_DIR)
	$(Q)cp -f $(CHART) $(SRCDIR)/chart-values.yaml $(RANCHER_DIR)/

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
	$(Q)podman image rm -f localhost/bigstack/rancher-upstream:v$(APP_VERSION) 2>/dev/null || true

BUILD += $(CLI_BIN) $(CHART)
BUILDCLEAN += $(CLI_BIN) $(CLI_SRC_DIR) $(CHART) $(RANCHER_DIR)

SUBDIRS += cpo

include $(HEX_MAKEDIR)/hex_sdk.mk
