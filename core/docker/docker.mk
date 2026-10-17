# Cube SDK
# Docker installation

DOCKER_DIR := /opt/docker

ROOTFS_DNF += containerd.io docker-ce docker-ce-cli docker-ce-rootless-extras skopeo

DOCKER_REPO = $(shell chroot $(ROOTDIR) dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo ; echo "docker")

# The Go binaries of containerd.io (containerd, ctr, gen-manpages, the runc shim and the runc it
# bundles), docker-compose-plugin and skopeo are rebuilt here from each vendor's release tag, at the
# version the package installs, and installed over the package's copies. Every vendor build is still
# made with a Go older than the October 2026 security release (1.27.2 / 1.26.9), or links an x/net
# older than its fix; the jail's Go and DOCKER_GO_GET cover both. The packages stay for their units,
# config and dependencies, and name the version in the SBOM. Return a binary to its vendor's on the
# condition core/exporters/Makefile gives. The packages float, so rootfs_install stops the build
# when one has moved past the version rebuilt here, rather than put an older binary under a newer
# package: bump the version below to the package's.
DOCKER_GO_GET := golang.org/x/crypto@v0.58.0 golang.org/x/net@v0.61.0 golang.org/x/text@v0.43.0
CONTAINERD_VER := 2.4.2
RUNC_VER := 1.5.2
COMPOSE_VER := 5.6.0
SKOPEO_VER := 1.22.2
DOCKER_GO_DIR := $(ARCS_DIR)/docker-go
DOCKER_GO_BIN := $(DOCKER_GO_DIR)/bin
# Raise the x/ modules in a clone; $(1) is extra, e.g. `go mod vendor` for a vendored tree
DOCKER_GO_RAISE = go get $(DOCKER_GO_GET) && go mod tidy $(1)

# $(1) name, $(2) tag, $(3) GitHub org/repo. The tag is cloned shallow, and the modules come from
# proxy.golang.org, checked against sum.golang.org.
define docker_go_clone
$$(DOCKER_GO_DIR)/$(1)-src:
	$$(call RUN_CMD_TIMED, rm -rf $$@.part && \
		git clone -q --depth 1 -b $(2) https://github.com/$(3).git $$@.part && \
		mv $$@.part $$@,"  CLONE   $(3)@$(2)")
endef

# containerd, ctr, gen-manpages and the runc shim, with the static tags and version ldflags of
# containerd's own Makefile (STATIC=1), btrfs left out as Docker's build does, and no_grpc for the
# shim, as there. The tree is vendored.
CONTAINERD_PKG := github.com/containerd/containerd/v2
CONTAINERD_TAGS := urfave_cli_no_docs no_btrfs osusergo netgo static_build
$(eval $(call docker_go_clone,containerd,v$(CONTAINERD_VER),containerd/containerd))
$(DOCKER_GO_DIR)/containerd.built: $(DOCKER_GO_DIR)/containerd-src $(COREDIR)/docker/docker.mk
	$(Q)mkdir -p $(DOCKER_GO_BIN)
	$(call RUN_CMD_TIMED, cd $< && $(call DOCKER_GO_RAISE,&& go mod vendor) && \
		L="-s -w -X $(CONTAINERD_PKG)/version.Version=v$(CONTAINERD_VER) \
			-X $(CONTAINERD_PKG)/version.Revision=$$(git rev-parse HEAD) \
			-X $(CONTAINERD_PKG)/version.Package=$(CONTAINERD_PKG)" && \
		for c in containerd ctr gen-manpages ; do \
			CGO_ENABLED=0 go build -mod=vendor -trimpath -tags "$(CONTAINERD_TAGS)" -ldflags "$$L" \
				-o $(DOCKER_GO_BIN)/$$c ./cmd/$$c || exit 1 ; \
		done && \
		CGO_ENABLED=0 go build -mod=vendor -trimpath -tags "$(CONTAINERD_TAGS) no_grpc" -ldflags "$$L" \
			-o $(DOCKER_GO_BIN)/containerd-shim-runc-v2 ./cmd/containerd-shim-runc-v2,"  BUILD   containerd")
	$(Q)touch $@

# runc, which containerd.io bundles. cgo for seccomp: the jail carries libseccomp-devel, and the
# image has libseccomp. libpathrs is left out: it is a Rust library, and runc 1.5 falls back to its
# Go path handling without it (RUNC_BUILDTAGS=-libpathrs upstream).
$(eval $(call docker_go_clone,runc,v$(RUNC_VER),opencontainers/runc))
$(DOCKER_GO_BIN)/runc: $(DOCKER_GO_DIR)/runc-src $(COREDIR)/docker/docker.mk
	$(Q)mkdir -p $(@D)
	$(call RUN_CMD_TIMED, cd $< && $(call DOCKER_GO_RAISE,&& go mod vendor) && \
		CGO_ENABLED=1 go build -mod=vendor -trimpath -buildmode=pie -tags "seccomp urfave_cli_no_docs" \
		-ldflags "-s -w -X main.gitCommit=$$(git rev-parse HEAD) -X main.version=$(RUNC_VER)" \
		-o $@ .,"  BUILD   runc")

$(eval $(call docker_go_clone,compose,v$(COMPOSE_VER),docker/compose))
$(DOCKER_GO_BIN)/docker-compose: $(DOCKER_GO_DIR)/compose-src $(COREDIR)/docker/docker.mk
	$(Q)mkdir -p $(@D)
	$(call RUN_CMD_TIMED, cd $< && $(DOCKER_GO_RAISE) && \
		CGO_ENABLED=0 go build -trimpath \
		-ldflags "-w -s -X github.com/docker/compose/v5/internal.Version=v$(COMPOSE_VER)" \
		-o $@ ./cmd,"  BUILD   docker-compose")

# skopeo, from the Stream rpm. Pure Go: containers_image_openpgp in place of gpgme (and of the
# sequoia library), with btrfs and devicemapper left out, as skopeo's own static build does.
$(eval $(call docker_go_clone,skopeo,v$(SKOPEO_VER),containers/skopeo))
$(DOCKER_GO_BIN)/skopeo: $(DOCKER_GO_DIR)/skopeo-src $(COREDIR)/docker/docker.mk
	$(Q)mkdir -p $(@D)
	$(call RUN_CMD_TIMED, cd $< && $(call DOCKER_GO_RAISE,&& go mod vendor) && \
		CGO_ENABLED=0 go build -mod=vendor -trimpath \
		-tags "containers_image_openpgp exclude_graphdriver_btrfs exclude_graphdriver_devicemapper" \
		-ldflags "-s -w" -o $@ ./cmd/skopeo,"  BUILD   skopeo")

# $(1) package, $(2) the version its binaries were rebuilt from
docker_go_check = v=$$(chroot $(ROOTDIR) rpm -q --qf '%{VERSION}' $(1)) && [ "$$v" = "$(2)" ] || \
	{ echo "docker.mk: $(1) is $$v, but its binaries are rebuilt from $(2)" ; exit 1 ; }

rootfs_install:: $(DOCKER_GO_DIR)/containerd.built $(DOCKER_GO_BIN)/runc $(DOCKER_GO_BIN)/docker-compose $(DOCKER_GO_BIN)/skopeo
	$(Q)$(call docker_go_check,containerd.io,$(CONTAINERD_VER))
	$(Q)$(call docker_go_check,docker-compose-plugin,$(COMPOSE_VER))
	$(Q)$(call docker_go_check,skopeo,$(SKOPEO_VER))
	$(Q)chroot $(ROOTDIR) /usr/bin/runc --version | grep -qx 'runc version $(RUNC_VER)' || \
		{ echo "docker.mk: containerd.io's runc is not $(RUNC_VER)" ; exit 1 ; }
	$(Q)cd $(DOCKER_GO_BIN) && install -m 0755 containerd ctr gen-manpages containerd-shim-runc-v2 runc skopeo \
		$(ROOTDIR)/usr/bin/
	$(Q)install -m 0755 $(DOCKER_GO_BIN)/docker-compose $(ROOTDIR)/usr/libexec/docker/cli-plugins/docker-compose

heavy_components_install::
	$(Q)chroot $(ROOTDIR) systemctl disable docker
	$(Q)chroot $(ROOTDIR) mkdir -p $(DOCKER_DIR)
	$(Q)cp -rf $(TOP_BLDDIR)/core/docker/registry/ $(ROOTDIR)/$(DOCKER_DIR)/
	$(Q)cp -f $(TOP_BLDDIR)/core/docker/registry@2.tar $(ROOTDIR)/$(DOCKER_DIR)/

# for RC builds
heavyfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf $(DOCKER_DIR)/registry
	$(Q)chroot $(ROOTDIR) rm -rf $(DOCKER_DIR)/registry@2.tar
	$(Q)cp -rf $(TOP_BLDDIR)/core/docker/registry/ $(ROOTDIR)/$(DOCKER_DIR)/
	$(Q)cp -f $(TOP_BLDDIR)/core/docker/registry@2.tar $(ROOTDIR)/$(DOCKER_DIR)/
