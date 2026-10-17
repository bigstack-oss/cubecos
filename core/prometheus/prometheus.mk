# Cube SDK
# Prometheus installation

# EPEL's `prometheus` is the 3.x line. packagecloud's `prometheus2` stops at 2.55.1 and
# every 2.x LTS is EOL (2.37 2023-07-31, 2.45 2024-07-31, 2.53 2025-07-31); 2.55 was never
# an LTS at all. 3.13 is the current LTS, supported to 2027-07-31.
#
# This also retires the source build that used to live in core/prometheus/Makefile. Its one
# real benefit was building against the jail's Go rather than a stale release toolchain, and
# when this moved to the rpm EPEL built 3.13.1 with go1.26.4, ahead of the jail's go1.25.12.
# That stopped holding when the jail moved to go1.27.1 (cubecos#801): govulncheck finds 22
# advisories in EPEL's 3.13.1 binary, 10 of them standard library and all fixed by go1.26.6,
# which a rebuild with the jail's Go would shed. That rebuild is below now, of the version the rpm
# installs, so the package identity holds. Using the rpm keeps that identity honest: syft
# catalogues an rpm-owned binary at the rpm's version (exclude-binary-overlap-by-ownership), so a
# source-built 3.x dropped on top of a 2.55.1 rpm would have been reported as 2.55.1 in the
# SBOM forever.
ROOTFS_DNF += prometheus

# prometheus and promtool are rebuilt from the release tag of the version EPEL's rpm installs and
# installed over the rpm's: EPEL's build is still made with a Go older than the October 2026
# security release (1.27.2 / 1.26.9), and links an x/net older than its fix. The jail's Go and
# PROMETHEUS_GO_GET cover both. Return to the rpm's binaries on the condition
# core/exporters/Makefile gives. EPEL floats, so rootfs_install stops the build when the rpm has
# moved past PROMETHEUS_VER, rather than put an older binary under a newer package: bump it to the
# rpm's, with the web UI's sha256 from that release's sha256sums.txt.
#
# The web UI is the release's own prebuilt assets, compressed and embedded by the repo's
# scripts/compress_assets.sh -- what its assets-compress target runs with SKIP_UI_BUILD -- so no
# node toolchain is needed. The script is run directly rather than through that make target, which
# would inherit this build's command-line variables. The tree carries a go.work, which -mod=mod is
# refused under. The build flags and version ldflags are the release's own.
PROMETHEUS_VER := 3.15.0
PROMETHEUS_GO_GET := golang.org/x/crypto@v0.58.0 golang.org/x/net@v0.61.0 golang.org/x/text@v0.43.0
PROMETHEUS_GO_DIR := $(ARCS_DIR)/prometheus-go
PROMETHEUS_SRC := $(PROMETHEUS_GO_DIR)/prometheus-$(PROMETHEUS_VER)-src
PROMETHEUS_UI := prometheus-web-ui-$(PROMETHEUS_VER).tar.gz
PROMETHEUS_UI_SHA256 := fa8c918ed05e3f89e232e9b69eccd6ed074602cd9e8a2cab7a92bec9651974ae
PROMETHEUS_VERSION_PKG := github.com/prometheus/common/version

# $(GITHUB_DL_BASE), as for thanos: a GitHub release asset, mirrored for the build network.
$(PROMETHEUS_GO_DIR)/$(PROMETHEUS_UI):
	$(Q)mkdir -p $(@D)
	$(Q)wget $(GITHUB_DL_BASE)/prometheus/prometheus/releases/download/v$(PROMETHEUS_VER)/$(PROMETHEUS_UI) -O $@.part
	$(Q)echo "$(PROMETHEUS_UI_SHA256)  $@.part" | sha256sum -c -
	$(Q)mv $@.part $@

$(PROMETHEUS_SRC):
	$(call RUN_CMD_TIMED, rm -rf $@.part && \
		git clone -q --depth 1 -b v$(PROMETHEUS_VER) https://github.com/prometheus/prometheus.git $@.part && \
		mv $@.part $@,"  CLONE   prometheus-$(PROMETHEUS_VER)")

$(PROMETHEUS_GO_DIR)/prometheus.built: $(PROMETHEUS_SRC) $(PROMETHEUS_GO_DIR)/$(PROMETHEUS_UI) $(COREDIR)/prometheus/prometheus.mk
	$(call RUN_CMD_TIMED, rm -rf $(PROMETHEUS_GO_DIR)/web-ui && mkdir -p $(PROMETHEUS_GO_DIR)/web-ui $(PROMETHEUS_GO_DIR)/bin && \
		tar -xzf $(PROMETHEUS_GO_DIR)/$(PROMETHEUS_UI) -C $(PROMETHEUS_GO_DIR)/web-ui && \
		cd $< && export GOWORK=off && \
		PREBUILT_ASSETS_STATIC_DIR=$(PROMETHEUS_GO_DIR)/web-ui/static scripts/compress_assets.sh && \
		go get $(PROMETHEUS_GO_GET) && go mod tidy && \
		L="-s -w -X $(PROMETHEUS_VERSION_PKG).Version=$(PROMETHEUS_VER) \
			-X $(PROMETHEUS_VERSION_PKG).Revision=$$(git rev-parse HEAD) -X $(PROMETHEUS_VERSION_PKG).Branch=HEAD \
			-X $(PROMETHEUS_VERSION_PKG).BuildUser=cubecos -X $(PROMETHEUS_VERSION_PKG).BuildDate=$$(date -u +%Y%m%d-%H:%M:%S)" && \
		for c in prometheus promtool ; do \
			CGO_ENABLED=0 go build -trimpath -tags "netgo builtinassets" -ldflags "$$L" \
				-o $(PROMETHEUS_GO_DIR)/bin/$$c ./cmd/$$c || exit 1 ; \
		done,"  BUILD   prometheus-$(PROMETHEUS_VER)")
	$(Q)touch $@

rootfs_install:: $(PROMETHEUS_GO_DIR)/prometheus.built
	$(Q)v=$$(chroot $(ROOTDIR) rpm -q --qf '%{VERSION}' prometheus) && [ "$$v" = "$(PROMETHEUS_VER)" ] || \
		{ echo "prometheus.mk: EPEL installed prometheus $$v, but its binaries are rebuilt from $(PROMETHEUS_VER)" ; exit 1 ; }
	$(Q)install -m 0755 $(PROMETHEUS_GO_DIR)/bin/prometheus $(PROMETHEUS_GO_DIR)/bin/promtool $(ROOTDIR)/usr/bin/

# This also drops packagecloud's prometheus.repo, which prometheus2 was its only consumer of.
# It was kept in reserve for the exporters, but it is stale everywhere it matters -- against
# upstream: node_exporter 1.9.0 vs 1.12.1, blackbox 0.26.0 vs 0.28.0, memcached 0.15.0 vs
# 0.17.0, apache 1.0.10 vs 1.1.1, mysqld 0.17.2 vs 0.20.0, snmp 0.28.0 vs 0.30.1, statsd
# 0.28.0 vs 0.31.0 -- the same neglect that left prometheus itself at 2.55.1. Of the exporters
# the telemetry replacement needs, EPEL carries only node-exporter (1.12.1, current), and no
# upstream exporter publishes an rpm at all: every one ships a linux-amd64.tar.gz and nothing
# else. So they come from EPEL where it has them and from the release tarballs otherwise, and
# there is no third-party rpm repo left to keep.

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p /var/log/prometheus
	$(Q)chroot $(ROOTDIR) chown prometheus:prometheus /var/log/prometheus
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/prometheus.service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/prometheus/prometheus-restart.conf ./etc/systemd/system/prometheus.service.d/
	$(Q)chroot $(ROOTDIR) systemctl disable prometheus
	$(Q)mv -f $(ROOTDIR)/etc/prometheus/prometheus.yml $(ROOTDIR)/etc/prometheus/prometheus.yml.org
