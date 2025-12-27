
# CUBE SDK

include ../../build.mk

SRCS                 := $(shell find $(SRCDIR)/src/ -name "*.tf")
RANCHER_PROV_REPO    := https://github.com/rancher/terraform-provider-rancher2.git
RANCHER_PROV_VER     := v7.0.0
RANCHER_PROV_DIR     := terraform-provider-rancher2
RANCHER_UPSTREAM_BIN := $(RANCHER_PROV_DIR)/bin/terraform-provider-rancher2

$(RANCHER_PROV_DIR):
	$(call RUN_CMD_TIMED,git clone -b $(RANCHER_PROV_VER) $(RANCHER_PROV_REPO) $(RANCHER_PROV_DIR),"  CLONE   provider")

$(RANCHER_UPSTREAM_BIN): $(RANCHER_PROV_DIR)
	$(call RUN_CMD_TIMED,cd $(RANCHER_PROV_DIR) && go get github.com/hashicorp/go-getter@v1.7.4 && go mod tidy, "  UPDATE  deps")
	$(call RUN_CMD_TIMED,cd $(RANCHER_PROV_DIR) && make build, "  BUILD   rancher-provider")

terraform: $(RANCHER_UPSTREAM_BIN)
	$(Q)cp -rfT $(SRCDIR)/src/ ./$@
	$(Q)make clean-etcd
	$(call RUN_CMD_TIMED,make run-etcd,"  RUN     etcd@jail")
	$(call RUN_CMD_TIMED,terraform -chdir=$@ init,"  INIT    $@")
	$(Q)cp -f $(RANCHER_UPSTREAM_BIN) \
        ./$@/.terraform/providers/registry.terraform.io/rancher/rancher2/7.0.0/linux_amd64/terraform-provider-rancher2_v7.0.0
	$(Q)make clean-etcd

install: terraform
	$(Q)cp -rfT $(SRCDIR)/src/ ./terraform
	$(Q)cp -rf ./terraform/ /var/lib/
	$(Q)cp -f $(SRCDIR)/scripts/* /usr/local/bin/

run-etcd:
	$(Q)podman run -d -p 12379:2379 --name=etcd quay.io/coreos/etcd:v3.5.23 etcd \
		--listen-client-urls http://0.0.0.0:2379 \
		--advertise-client-urls=http://0.0.0.0:2379

clean-etcd:
	$(Q)podman rm -if etcd $(QEND)

clean::
	$(Q)rm -rf /var/lib/terraform/
	$(Q)rm -f /usr/local/bin/terraform-cube.sh
	$(Q)rm -f /usr/local/bin/terraform-action.sh
	$(Q)make clean-etcd

BUILD += terraform
BUILDCLEAN += terraform

include $(HEX_MAKEDIR)/hex_sdk.mk
