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
# 5.x still serves the SDKv2 plugin protocol 5, so terraform-core below can drive it.
#
# Keep the required_providers pins in src/keycloak/**/main.tf in step with this.
KEYCLOAK_PROV_VER     := v5.9.0
KEYCLOAK_PROV_SEMVER  := $(patsubst v%,%,$(KEYCLOAK_PROV_VER))
KEYCLOAK_PROV_DIR     := terraform-provider-keycloak
KEYCLOAK_UPSTREAM_BIN := $(KEYCLOAK_PROV_DIR)/terraform-provider-keycloak
TF_CORE_REPO          := https://github.com/hashicorp/terraform.git
# 1.2.9 is as far as terraform-core can go here. The state lives in etcd through the etcdv3
# backend (src/main.tf), and 1.3.0 removed that backend; 1.6.0 onwards is also under the BUSL
# rather than the MPL 2.0, which this build does not take. Every 1.x up to 1.2.9 still drives
# the providers' plugin protocol 5 and reads and writes state format 4 exactly as 0.14 did, so a
# control node on the previous release and one on this release share the same state through a
# rolling upgrade: neither refuses a snapshot the other wrote.
TF_CORE_VER           := v1.2.9
TF_CORE_DIR           := terraform-core
TF_CORE_BIN           := $(TF_CORE_DIR)/terraform-core
# Applied in order over the clone; see the recipe below
TF_CORE_PATCHES       := $(SRCDIR)/tf-core-patches/etcd-client-v3.5.patch $(SRCDIR)/tf-core-patches/snapshotfs-chown.patch
# The x/ modules at the October 2026 Go security release, as core/gorebuild, and grpc at the
# latest release, which needs no http2.TrailerPrefix from x/net. Raised in all three binaries.
TF_GO_GET             := golang.org/x/crypto@v0.58.0 golang.org/x/net@v0.61.0 golang.org/x/text@v0.43.0 \
	google.golang.org/grpc@v1.84.0

$(RANCHER_PROV_DIR):
	$(call RUN_CMD_TIMED,git clone -b $(RANCHER_PROV_VER) $(RANCHER_PROV_REPO) $(RANCHER_PROV_DIR),"  CLONE   rancher-provider")

# x/crypto, x/net, x/text and grpc are lifted past v7.0.0's to TF_GO_GET. go-getter goes to the
# 1.8 line: no 1.7 release carries all of its fixes. v7.0.0 replaces k8s.io/kubernetes with
# v1.30.1; the replace stays on the 1.30 line, at its last release.
RANCHER_PROV_K8S      := v1.30.14
$(RANCHER_UPSTREAM_BIN): $(RANCHER_PROV_DIR)
	$(call RUN_CMD_TIMED,cd $(RANCHER_PROV_DIR) && go get github.com/hashicorp/go-getter@v1.8.10 && \
		go get $(TF_GO_GET) && \
		go mod edit -replace k8s.io/kubernetes=k8s.io/kubernetes@$(RANCHER_PROV_K8S) && \
		go mod tidy, "  UPDATE  rancher-provider")
	$(call RUN_CMD_TIMED,cd $(RANCHER_PROV_DIR) && make build, "  BUILD   rancher-provider")

$(KEYCLOAK_PROV_DIR):
	$(call RUN_CMD_TIMED,git clone -b $(KEYCLOAK_PROV_VER) $(KEYCLOAK_PROV_REPO) $(KEYCLOAK_PROV_DIR),"  CLONE   keycloak-provider")

# x/net, x/text and grpc are lifted past v5.9.0's to TF_GO_GET (x/crypto is not linked).
$(KEYCLOAK_UPSTREAM_BIN): $(KEYCLOAK_PROV_DIR)
	$(call RUN_CMD_TIMED,cd $(KEYCLOAK_PROV_DIR) && go get $(TF_GO_GET) && go mod tidy, "  UPDATE  keycloak-provider")
	$(call RUN_CMD_TIMED,cd $(KEYCLOAK_PROV_DIR) && \
		CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		go build \
		-gcflags "all=-N -l" -trimpath -ldflags " -X main.version=$(KEYCLOAK_PROV_VER)" \
		-o terraform-provider-keycloak ., \
		"  BUILD   keycloak-provider")

$(TF_CORE_DIR):
	$(call RUN_CMD_TIMED,git clone -b $(TF_CORE_VER) $(TF_CORE_REPO) $(TF_CORE_DIR),"  CLONE   tf-core")

# 1.2.9's etcd backends are written against etcd's pre-3.5 client, which needs grpc v1.27.1 --
# 1.2.9 replaces grpc with it -- and that grpc holds x/net back. The first patch moves both
# backends to the 3.5 client modules, the line of the etcd we run: only the import paths change,
# the client API is the same. With it the grpc replace goes, and the modules can be raised. The
# second patch gives the configuration snapshot's filesystem the Chown that afero's Fs interface
# gained after 1.2.9's afero, since the raised modules bring a newer afero in.
#
# The patches are applied to a clean checkout each time, so the recipe can be rerun on a clone.
# go-slug and golang-jwt/v4 are raised past 1.2.9's for their fixes as well.
$(TF_CORE_BIN): $(TF_CORE_DIR) $(TF_CORE_PATCHES)
	$(call RUN_CMD_TIMED,cd $(TF_CORE_DIR) && git checkout -q -- . && git apply $(TF_CORE_PATCHES) && \
		go mod edit -dropreplace=google.golang.org/grpc@v1.36.1 && \
		go get go.etcd.io/etcd/client/v3@v3.5.34 go.etcd.io/etcd/client/v2@v2.305.34 && \
		go get $(TF_GO_GET) github.com/hashicorp/go-getter@v1.8.10 \
			github.com/hashicorp/go-slug@v0.18.4 github.com/golang-jwt/jwt/v4@v4.5.2 && \
		go mod tidy, \
		"  UPDATE  tf-core")
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
	$(Q)podman run -d -p 12379:2379 --name=etcd quay.io/coreos/etcd:v3.5.34 etcd \
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
