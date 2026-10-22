# Cube SDK
# thanos installation

THANOS_VER := 0.42.4
# Built from the release tag rather than taken from the release tarball: the release is built with
# a Go older than the October 2026 security release (1.27.2 / 1.26.9), and links an x/net, x/text,
# x/crypto, grpc and klauspost/compress older than their fixes. The jail's Go and THANOS_GO_GET
# cover both. Return to the tarball on the condition core/exporters/Makefile gives. The web UI is
# the React build the repo commits under pkg/ui/static, embedded as the release does, and the tags
# and version ldflags are the release's own (.promu.yml). The tag is cloned shallow, and the
# modules come from proxy.golang.org, checked against sum.golang.org.
THANOS_GO_GET := golang.org/x/crypto@v0.58.0 golang.org/x/net@v0.61.0 golang.org/x/text@v0.43.0 \
	google.golang.org/grpc@v1.84.0 github.com/klauspost/compress@v1.18.7
THANOS_GO_DIR := $(ARCS_DIR)/thanos-go
THANOS_SRC := $(THANOS_GO_DIR)/thanos-$(THANOS_VER)-src
THANOS_BIN := $(THANOS_GO_DIR)/bin/thanos
THANOS_VERSION_PKG := github.com/prometheus/common/version
# A variable, so the comma stays out of RUN_CMD_TIMED's arguments
THANOS_TAGS := netgo,slicelabels

$(THANOS_SRC):
	$(call RUN_CMD_TIMED, rm -rf $@.part && \
		git clone -q --depth 1 -b v$(THANOS_VER) https://github.com/thanos-io/thanos.git $@.part && \
		mv $@.part $@,"  CLONE   thanos-$(THANOS_VER)")

$(THANOS_BIN): $(THANOS_SRC) $(COREDIR)/thanos/thanos.mk
	$(Q)mkdir -p $(@D)
	$(call RUN_CMD_TIMED, cd $< && go get $(THANOS_GO_GET) && go mod tidy && \
		CGO_ENABLED=0 go build -trimpath -tags $(THANOS_TAGS) \
		-ldflags "-X $(THANOS_VERSION_PKG).Version=$(THANOS_VER) -X $(THANOS_VERSION_PKG).Revision=$$(git rev-parse HEAD) \
			-X $(THANOS_VERSION_PKG).Branch=HEAD -X $(THANOS_VERSION_PKG).BuildUser=cubecos \
			-X $(THANOS_VERSION_PKG).BuildDate=$$(date -u +%Y%m%d-%H:%M:%S)" \
		-o $@ ./cmd/thanos,"  BUILD   thanos-$(THANOS_VER)")

rootfs_install:: $(THANOS_BIN)
	$(Q)install -m 0755 $(THANOS_BIN) $(ROOTDIR)/usr/bin/thanos
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/thanos
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/thanos/thanos-sidecar.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/thanos/thanos-query.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/thanos/thanos-store.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/thanos/thanos-compact.service ./lib/systemd/system
	$(Q)chroot $(ROOTDIR) mkdir -p /var/lib/thanos/store /var/lib/thanos/compact
	$(Q)chroot $(ROOTDIR) chown -R prometheus:prometheus /var/lib/thanos
	$(Q)chroot $(ROOTDIR) systemctl disable thanos-sidecar
	$(Q)chroot $(ROOTDIR) systemctl disable thanos-query
	$(Q)chroot $(ROOTDIR) systemctl disable thanos-store
	# thanos-compact is pacemaker-managed and must never be enabled in systemd:
	# two compactors on one bucket corrupt it. See thanos-compact.service.
	$(Q)chroot $(ROOTDIR) systemctl disable thanos-compact
