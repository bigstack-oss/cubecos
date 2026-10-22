# Cube SDK
# Kapacitor installation

# Installed from the InfluxData repo core/influxdb/influxdb.repo already configures,
# not from an explicit dl.influxdata.com URL as it was through 1.5.7. The reason is
# verification: the rpms published under dl.influxdata.com/kapacitor/releases/ carry
# `Signature : (none)`, so that path installed an unsigned 87 MB binary, while the same
# build in the repo is signed (RSA/SHA512, key id da61c26a0585bd3b) and dnf checks it.
#
# Pinned in both directions. ROOTFS_DNF names the exact NVR so the build installs 1.8.8-1
# rather than whatever the channel has moved to, and LOCKED_DNF stops installdnf's
# duplicate pass from resolving it to something else -- the same pairing qemu and openssl
# use in core/heavyfs/Makefile. No epoch: LOCKED_DNF is matched as a string against rpm
# filenames and a filename never carries one (see the qemu note there).
KAPACITOR_VER := 1.8.8-1

ROOTFS_DNF += kapacitor-$(KAPACITOR_VER)
LOCKED_DNF += kapacitor-$(KAPACITOR_VER)

# kapacitord, kapacitor and tickfmt are rebuilt from the release tag of that version and installed
# over the rpm's, as influxdb.mk does for influxd. InfluxData's build is made with a Go older than
# the October 2026 security release, links an x/net older than its fixes and a client_golang older
# than its fix, and links the github.com/docker/docker module, whose matches have no fixed release
# (they are fixed only in the moby/moby modules that replace it). The rebuild raises the x/
# modules, grpc and klauspost/compress, and moves services/swarm and its test helpers from
# docker/docker's api/types to the same types in github.com/moby/moby/api.
# - Flux moves to 0.200.0, influxdb 1.13.1's: 1.8.8's 0.191.0 needs the Rust 1.72 the release was
#   built with, and the jail's newer rustc rejects its libflux. 0.200.0 brings client_golang
#   1.19.0, past its fix, and pgx/v5 5.8.0, raised to its fixed release.
# - prometheus/common stays at the 0.20.0 1.8.8 pins: the 2021 prometheus discovery code kapacitor
#   links does not compile against the newer common those require.
# The release links statically against musl, this build dynamically against the image's glibc.
KAPACITOR_SRC_VER := $(firstword $(subst -, ,$(KAPACITOR_VER)))
KAPACITOR_GO_GET := golang.org/x/crypto@v0.58.0 golang.org/x/net@v0.61.0 golang.org/x/text@v0.43.0 \
	google.golang.org/grpc@v1.84.0 github.com/moby/moby/api@v1.56.1 \
	github.com/influxdata/flux@v0.200.0 github.com/jackc/pgx/v5@v5.11.0 \
	github.com/klauspost/compress@v1.18.7
KAPACITOR_GO_DIR := $(ARCS_DIR)/kapacitor-go
KAPACITOR_SRC := $(KAPACITOR_GO_DIR)/kapacitor-$(KAPACITOR_SRC_VER)-src
KAPACITOR_CMDS := cmd/kapacitord cmd/kapacitor tick/cmd/tickfmt
KAPACITOR_DOCKER := github.com/docker/docker/api/types
KAPACITOR_MOBY := github.com/moby/moby/api/types
# A variable, so the commas stay out of RUN_CMD_TIMED's arguments
KAPACITOR_TAGS := netgo,osusergo

$(KAPACITOR_SRC):
	$(call RUN_CMD_TIMED, rm -rf $@.part && \
		git clone -q --depth 1 -b v$(KAPACITOR_SRC_VER) https://github.com/influxdata/kapacitor.git $@.part && \
		mv $@.part $@,"  CLONE   kapacitor-$(KAPACITOR_SRC_VER)")

$(KAPACITOR_GO_DIR)/kapacitor.built: $(KAPACITOR_SRC) $(COREDIR)/kapacitor/kapacitor.mk
	$(Q)mkdir -p $(KAPACITOR_GO_DIR)/bin
	$(call RUN_CMD_TIMED, cd $< && { grep -q '"$(KAPACITOR_MOBY)/swarm"' services/swarm/client/client.go || \
		{ f=$$(grep -rl '"$(KAPACITOR_DOCKER)' --include=*.go .) && [ -n "$$f" ] && \
		sed -i -e 's#"$(KAPACITOR_DOCKER)/swarm"#"$(KAPACITOR_MOBY)/swarm"#' \
			-e 's#"$(KAPACITOR_DOCKER)/system"#"$(KAPACITOR_MOBY)/system"#' \
			-e 's#"$(KAPACITOR_DOCKER)"#"$(KAPACITOR_MOBY)/common"#' \
			-e 's#types\.ErrorResponse#common.ErrorResponse#' $$f ; } ; } && \
		go get $(KAPACITOR_GO_GET) && \
		go mod edit -replace github.com/prometheus/common=github.com/prometheus/common@v0.20.0 && \
		go mod tidy && export PKG_CONFIG=$$PWD/pkg-config.sh && \
		for c in $(KAPACITOR_CMDS) ; do \
			go build -trimpath -tags $(KAPACITOR_TAGS) -buildmode=pie \
				-ldflags "-s -w -X main.version=$(KAPACITOR_SRC_VER) -X main.branch=HEAD -X main.commit=$$(git rev-parse HEAD) -X main.platform=OSS" \
				-o $(KAPACITOR_GO_DIR)/bin/$$(basename $$c) ./$$c || exit 1 ; \
		done,"  BUILD   kapacitor-$(KAPACITOR_SRC_VER)")
	$(Q)touch $@

rootfs_install:: $(KAPACITOR_GO_DIR)/kapacitor.built
	$(Q)v=$$(chroot $(ROOTDIR) rpm -q --qf '%{VERSION}' kapacitor) && [ "$$v" = "$(KAPACITOR_SRC_VER)" ] || \
		{ echo "kapacitor.mk: kapacitor $$v is installed, but its binaries are rebuilt from $(KAPACITOR_SRC_VER)" ; exit 1 ; }
	$(Q)cd $(KAPACITOR_GO_DIR)/bin && install -m 0755 kapacitord kapacitor tickfmt $(ROOTDIR)/usr/bin/

rootfs_install::
	$(Q)chroot $(ROOTDIR) systemctl disable kapacitor
	$(Q)mv -f $(ROOTDIR)/etc/kapacitor/kapacitor.conf $(ROOTDIR)/etc/kapacitor/kapacitor.conf.org
	$(Q)cp -f $(COREDIR)/kapacitor/kapacitor.conf $(ROOTDIR)/etc/kapacitor/kapacitor.conf.def
	$(Q)cp -rf $(COREDIR)/kapacitor/tasks $(ROOTDIR)/etc/kapacitor/
	$(Q)cp -rf $(COREDIR)/kapacitor/templates $(ROOTDIR)/etc/kapacitor/
	$(Q)cp -rf $(COREDIR)/kapacitor/handlers $(ROOTDIR)/etc/kapacitor/
	$(Q)cp -rf $(COREDIR)/kapacitor/exec_job_templates $(ROOTDIR)/etc/kapacitor/
	$(Q)mkdir -p $(ROOTDIR)/etc/kapacitor/config_handlers $(ROOTDIR)/var/alert_resp $(ROOTDIR)/var/response
	$(Q)mkdir -p $(ROOTDIR)/usr/share/cube/cos/kapacitor
	$(Q)cp -f $(COREDIR)/kapacitor/event.yaml $(ROOTDIR)/usr/share/cube/cos/kapacitor/

# smtp delivery watcher; cron.d skips file names containing a dot
rootfs_install::
	$(Q)mkdir -p $(ROOTDIR)/etc/cron.d
	$(Q)cp -f $(COREDIR)/kapacitor/alert_smtp_check.cron $(ROOTDIR)/etc/cron.d/alert_smtp_check
	$(Q)chmod 0644 $(ROOTDIR)/etc/cron.d/alert_smtp_check
