# CUBE SDK

include ../../build.mk

SRCS                  := $(shell find $(SRCDIR)/src/ -name "*.tf")
RANCHER_PROV_REPO     := https://github.com/rancher/terraform-provider-rancher2.git
RANCHER_PROV_VER      := v7.0.0
RANCHER_PROV_DIR      := terraform-provider-rancher2
RANCHER_UPSTREAM_BIN  := $(RANCHER_PROV_DIR)/bin/terraform-provider-rancher2
KEYCLOAK_PROV_REPO    := https://github.com/keycloak/terraform-provider-keycloak.git
# 5.x is the line written against Keycloak 26, the server we deploy: 5.8.0 dropped support
# for anything older and 5.9.0 is tested up to 26.7.0. The provider moved to the Keycloak
# organization in 4.5.0 and is published as keycloak/keycloak from then on, while
# mrparkers/keycloak ends at 4.4.0 -- so this is a namespace switch as well as a version
# bump. The `terraform init` below resolves the source from the public registry before the
# locally built binary is copied over it, which is why the namespace has to match there,
# and terraform-action.sh rewrites the old address in state that older releases wrote.
#
# 5.x still serves the SDKv2 plugin protocol 5, so terraform-core v0.14.3 below can drive it.
#
# Keep the required_providers pins in src/keycloak/**/main.tf in step with this.
KEYCLOAK_PROV_VER     := v5.9.0
KEYCLOAK_PROV_SEMVER  := $(patsubst v%,%,$(KEYCLOAK_PROV_VER))
KEYCLOAK_PROV_DIR     := terraform-provider-keycloak
KEYCLOAK_UPSTREAM_BIN := $(KEYCLOAK_PROV_DIR)/terraform-provider-keycloak
TF_CORE_REPO          := https://github.com/hashicorp/terraform.git
TF_CORE_VER           := v0.14.3
TF_CORE_DIR           := terraform-core
TF_CORE_BIN           := $(TF_CORE_DIR)/terraform-core

$(RANCHER_PROV_DIR):
	$(call RUN_CMD_TIMED,git clone -b $(RANCHER_PROV_VER) $(RANCHER_PROV_REPO) $(RANCHER_PROV_DIR),"  CLONE   rancher-provider")

# x/crypto and grpc are lifted past v7.0.0's 0.33.0 and 1.70.0 to their latest releases. Not the
# lowest fixed ones: x/crypto 0.52.0+ pulls x/net 0.54.0+, which drops http2.TrailerPrefix, and
# grpc's server transport still uses it in 1.79.3 through 1.82.0.
$(RANCHER_UPSTREAM_BIN): $(RANCHER_PROV_DIR)
	$(call RUN_CMD_TIMED,cd $(RANCHER_PROV_DIR) && go get github.com/hashicorp/go-getter@v1.7.4 && \
		go get golang.org/x/crypto@v0.57.0 google.golang.org/grpc@v1.84.0 && go mod tidy, "  UPDATE  rancher-provider")
	$(call RUN_CMD_TIMED,cd $(RANCHER_PROV_DIR) && make build, "  BUILD   rancher-provider")

$(KEYCLOAK_PROV_DIR):
	$(call RUN_CMD_TIMED,git clone -b $(KEYCLOAK_PROV_VER) $(KEYCLOAK_PROV_REPO) $(KEYCLOAK_PROV_DIR),"  CLONE   keycloak-provider")

# 4.4.0 needed golang.org/x/crypto lifted to v0.31.0 for its CVEs. 5.9.0 already requires
# v0.54.0, and a `go get` of the old floor would now be a downgrade, so it is gone.
$(KEYCLOAK_UPSTREAM_BIN): $(KEYCLOAK_PROV_DIR)
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
	@#    - x/crypto: v0.57.0, the latest. It pulls x/net v0.58.0, past the v0.54.0 that drops
	@#      http2.TrailerPrefix, and the pinned gRPC v1.29.1 still uses it, so x/net is held at
	@#      v0.53.0, which has it.
	$(call RUN_CMD_TIMED,cd $(TF_CORE_DIR) && \
		go get github.com/hashicorp/go-getter@v1.7.4 && \
		go get golang.org/x/crypto@v0.57.0 && \
		go mod edit -replace github.com/hashicorp/consul=github.com/hashicorp/consul@v1.5.0 && \
		go mod edit -replace google.golang.org/grpc=google.golang.org/grpc@v1.29.1 && \
		go mod edit -replace google.golang.org/api=google.golang.org/api@v0.34.0 && \
		go mod edit -replace cloud.google.com/go/storage=cloud.google.com/go/storage@v1.10.0 && \
		go mod edit -replace golang.org/x/net=golang.org/x/net@v0.53.0 && \
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

# The .tf sources are a prerequisite: without them make keeps a tree built
# before the last source change, and terraform.mk ships that stale tree next to
# an override.tfrc taken fresh from source -- a pair that can disagree about
# which providers are needed. Rebuild from scratch too, since cp -rfT merges
# and would leave a module that source has since deleted.
TF_SRCS := $(shell find $(SRCDIR)/src -type f 2>/dev/null)

terraform: $(TF_CORE_BIN) $(RANCHER_UPSTREAM_BIN) $(KEYCLOAK_UPSTREAM_BIN) $(TF_SRCS)
	$(Q)rm -rf ./$@
	$(Q)cp -rfT $(SRCDIR)/src/ ./$@
	$(Q)make clean-etcd
	$(call RUN_CMD_TIMED,make run-etcd,"  RUN     etcd@jail")
	$(call RUN_CMD_TIMED,$(TF_CORE_BIN) -chdir=$@ init,"  INIT    $@")
	$(Q)cp -f $(RANCHER_UPSTREAM_BIN) \
        ./$@/.terraform/providers/registry.terraform.io/rancher/rancher2/7.0.0/linux_amd64/terraform-provider-rancher2_v7.0.0
	$(Q)cp -f $(KEYCLOAK_UPSTREAM_BIN) \
		./$@/.terraform/providers/registry.terraform.io/keycloak/keycloak/$(KEYCLOAK_PROV_SEMVER)/linux_amd64/terraform-provider-keycloak_$(KEYCLOAK_PROV_VER)
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
