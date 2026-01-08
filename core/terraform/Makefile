# CUBE SDK

include ../../build.mk

SRCS                  := $(shell find $(SRCDIR)/src/ -name "*.tf")
RANCHER_PROV_REPO     := https://github.com/rancher/terraform-provider-rancher2.git
RANCHER_PROV_VER      := v7.0.0
RANCHER_PROV_DIR      := terraform-provider-rancher2
RANCHER_UPSTREAM_BIN  := $(RANCHER_PROV_DIR)/bin/terraform-provider-rancher2
KEYCLOAK_PROV_REPO    := https://github.com/mrparkers/terraform-provider-keycloak.git
KEYCLOAK_PROV_VER     := v3.10.0
KEYCLOAK_PROV_DIR     := terraform-provider-keycloak
KEYCLOAK_UPSTREAM_BIN := $(KEYCLOAK_PROV_DIR)/terraform-provider-keycloak
TF_CORE_REPO          := https://github.com/hashicorp/terraform.git
TF_CORE_VER           := v0.14.3
TF_CORE_DIR           := terraform-core
TF_CORE_BIN           := $(TF_CORE_DIR)/terraform-core

$(RANCHER_PROV_DIR):
	$(call RUN_CMD_TIMED,git clone -b $(RANCHER_PROV_VER) $(RANCHER_PROV_REPO) $(RANCHER_PROV_DIR),"  CLONE   rancher-provider")

$(RANCHER_UPSTREAM_BIN): $(RANCHER_PROV_DIR)
	$(call RUN_CMD_TIMED,cd $(RANCHER_PROV_DIR) && go get github.com/hashicorp/go-getter@v1.7.4 && go mod tidy, "  UPDATE  rancher-provider")
	$(call RUN_CMD_TIMED,cd $(RANCHER_PROV_DIR) && make build, "  BUILD   rancher-provider")

$(KEYCLOAK_PROV_DIR):
	$(call RUN_CMD_TIMED,git clone -b $(KEYCLOAK_PROV_VER) $(KEYCLOAK_PROV_REPO) $(KEYCLOAK_PROV_DIR),"  CLONE   keycloak-provider")

$(KEYCLOAK_UPSTREAM_BIN): $(KEYCLOAK_PROV_DIR)
	$(call RUN_CMD_TIMED,cd $(KEYCLOAK_PROV_DIR) && \
		go get golang.org/x/crypto@v0.31.0 && \
		go mod tidy, "  UPDATE  keycloak-provider")
	$(call RUN_CMD_TIMED,cd $(KEYCLOAK_PROV_DIR) && \
		CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		go build \
		-gcflags "all=-N -l" -trimpath -ldflags " -X main.version=$(KEYCLOAK_PROV_VER)" \
		-o terraform-provider-keycloak ., \
		"  BUILD   keycloak-provider")

$(TF_CORE_DIR):
	$(call RUN_CMD_TIMED,git clone -b $(TF_CORE_VER) $(TF_CORE_REPO) $(TF_CORE_DIR),"  CLONE   tf-core")

$(TF_CORE_BIN): $(TF_CORE_DIR)
	@# 1. DELETE TESTS
	@#    Consul v1.5.0 removed 'testutil', so these old test files are now broken.
	@#    We delete them because we only need the binary, not the tests.
	$(call RUN_CMD_TIMED,cd $(TF_CORE_DIR) && \
		find backend/remote-state/consul -name "*_test.go" -delete, \
		"  CLEAN   tf-core")

	@# 2. UPDATE DEPENDENCIES
	@#    - Consul: v1.5.0 (Min version with api/go.mod "Border" to fix Ambiguous Import)
	@#    - gRPC: v1.29.1 (Min version with 'naming' package required by Etcd)
	@#    - API: v0.34.0 (Goldilocks version: Has 'ImpersonateCredentials' but works with gRPC 1.29)
	@#    - Storage: v1.10.0 (MUST MATCH API v0.34.0)
	$(call RUN_CMD_TIMED,cd $(TF_CORE_DIR) && \
		go get github.com/hashicorp/go-getter@v1.7.4 && \
		go get golang.org/x/crypto@v0.31.0 && \
		go mod edit -replace github.com/hashicorp/consul=github.com/hashicorp/consul@v1.5.0 && \
		go mod edit -replace google.golang.org/grpc=google.golang.org/grpc@v1.29.1 && \
		go mod edit -replace google.golang.org/api=google.golang.org/api@v0.34.0 && \
		go mod edit -replace cloud.google.com/go/storage=cloud.google.com/go/storage@v1.10.0 && \
		go mod tidy, \
		"  UPDATE  tf-core")

	@# 3. Build
	$(call RUN_CMD_TIMED,cd $(TF_CORE_DIR) && \
		CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		go build \
		-trimpath \
		-ldflags="-s -w -X 'github.com/hashicorp/terraform/version.dev=no'" \
		-o terraform-core ., \
		"  BUILD   tf-core")

terraform: $(TF_CORE_BIN) $(RANCHER_UPSTREAM_BIN) $(KEYCLOAK_UPSTREAM_BIN)
	$(Q)cp -rfT $(SRCDIR)/src/ ./$@
	$(Q)make clean-etcd
	$(call RUN_CMD_TIMED,make run-etcd,"  RUN     etcd@jail")
	$(call RUN_CMD_TIMED,$(TF_CORE_BIN) -chdir=$@ init,"  INIT    $@")
	$(Q)cp -f $(RANCHER_UPSTREAM_BIN) \
        ./$@/.terraform/providers/registry.terraform.io/rancher/rancher2/7.0.0/linux_amd64/terraform-provider-rancher2_v7.0.0
	$(Q)cp -f $(KEYCLOAK_UPSTREAM_BIN) \
		./$@/.terraform/providers/registry.terraform.io/mrparkers/keycloak/3.10.0/linux_amd64/terraform-provider-keycloak_v3.10.0
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
BUILDCLEAN += terraform $(RANCHER_UPSTREAM_BIN) $(RANCHER_PROV_DIR) $(KEYCLOAK_UPSTREAM_BIN) $(KEYCLOAK_PROV_DIR) $(TF_CORE_BIN) $(TF_CORE_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
