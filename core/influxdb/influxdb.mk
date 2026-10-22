# Cube SDK
# Influxdb installation

# The influxdb python client was installed here for ceph's influx mgr module, which
# config_ceph.cpp now retires (RetireMgrInflux), and nothing else imports it. It goes from pip
# and, as the rpm ceph-mgr only recommends, through the blocklist -- with msgpack in both
# places, which only the client requires and which carries known vulnerabilities in both.
# toml, installed alongside it, stays.
ROOTFS_PIP += toml
BLKLST_DNF += python3-influxdb python3-msgpack

ROOTFS_DNF += influxdb
# InfluxData's key signs its repository, which influxdb and kapacitor come from, and telegraf
GPGKEY_DNF += $(COREDIR)/influxdb/RPM-GPG-KEY-influxdata 24C975CBA61A024EE1B631787C3D57159FC2F927

# influxd, influx and influx_inspect are rebuilt from the release tag of the version InfluxData's
# rpm installs and installed over the rpm's: its build is made with a Go older than the October
# 2026 security release (1.27.2 / 1.26.9), and links an x/net, x/text, grpc and klauspost/compress
# older than their fixes. The jail's Go and INFLUXDB_GO_GET cover both, with influxd's
# opentelemetry and go-jose raised to their fixed releases as well. So is the prometheus module,
# for the prompb types its remote read and write endpoints use: 1.13.1 pins a 2020 commit. 0.311.3
# is the first release past both of its fixed lines; prometheus/common moves with it. Return to the
# rpm's binaries on the condition core/exporters/Makefile gives. The repo floats, so rootfs_install
# stops the build when the rpm has moved past INFLUXDB_VER, rather than put an older binary under a
# newer package.
#
# All three link Flux (influxdb.conf enables it), whose libflux is Rust: the repo's pkg-config.sh
# has influxdata/pkg-config run `cargo build --release` on the flux module, with the crates pinned
# by flux's own Cargo.lock, so the jail carries rust and cargo. The tags, PIE and version ldflags
# are the release's own; the release links statically against musl, this build dynamically
# against the image's glibc.
INFLUXDB_VER := 1.13.1
INFLUXDB_GO_GET := golang.org/x/crypto@v0.58.0 golang.org/x/net@v0.61.0 golang.org/x/text@v0.43.0 \
	google.golang.org/grpc@v1.84.0 go.opentelemetry.io/otel@v1.47.0 go.opentelemetry.io/otel/sdk@v1.47.0 \
	github.com/go-jose/go-jose/v4@v4.1.6 github.com/prometheus/prometheus@v0.311.3 \
	github.com/klauspost/compress@v1.18.7
INFLUXDB_GO_DIR := $(ARCS_DIR)/influxdb-go
INFLUXDB_SRC := $(INFLUXDB_GO_DIR)/influxdb-$(INFLUXDB_VER)-src
INFLUXDB_BINS := influxd influx influx_inspect
# A variable, so the commas stay out of RUN_CMD_TIMED's arguments
INFLUXDB_TAGS := netgo,osusergo

# The tag is cloned shallow, and the modules come from proxy.golang.org, checked against
# sum.golang.org.
$(INFLUXDB_SRC):
	$(call RUN_CMD_TIMED, rm -rf $@.part && \
		git clone -q --depth 1 -b v$(INFLUXDB_VER) https://github.com/influxdata/influxdb.git $@.part && \
		mv $@.part $@,"  CLONE   influxdb-$(INFLUXDB_VER)")

$(INFLUXDB_GO_DIR)/influxdb.built: $(INFLUXDB_SRC) $(COREDIR)/influxdb/influxdb.mk
	$(Q)mkdir -p $(INFLUXDB_GO_DIR)/bin
	$(call RUN_CMD_TIMED, cd $< && go get $(INFLUXDB_GO_GET) && go mod tidy && \
		export PKG_CONFIG=$$PWD/pkg-config.sh && \
		for c in $(INFLUXDB_BINS) ; do \
			go build -trimpath -tags $(INFLUXDB_TAGS) -buildmode=pie \
				-ldflags "-s -w -X main.version=$(INFLUXDB_VER) -X main.branch= -X main.commit=$$(git rev-parse HEAD)" \
				-o $(INFLUXDB_GO_DIR)/bin/$$c ./cmd/$$c || exit 1 ; \
		done,"  BUILD   influxdb-$(INFLUXDB_VER)")
	$(Q)touch $@

rootfs_install:: $(INFLUXDB_GO_DIR)/influxdb.built
	$(Q)v=$$(chroot $(ROOTDIR) rpm -q --qf '%{VERSION}' influxdb) && [ "$$v" = "$(INFLUXDB_VER)" ] || \
		{ echo "influxdb.mk: the repo installed influxdb $$v, but its binaries are rebuilt from $(INFLUXDB_VER)" ; exit 1 ; }
	$(Q)cd $(INFLUXDB_GO_DIR)/bin && install -m 0755 $(INFLUXDB_BINS) $(ROOTDIR)/usr/bin/

INFLUXDB_REPO = $(shell cp $(COREDIR)/influxdb/influxdb.repo $(ROOTDIR)/etc/yum.repos.d/ ; echo "influxdb")

rootfs_install::
	$(Q)chroot $(ROOTDIR) systemctl disable influxdb
	$(Q)mv -f $(ROOTDIR)/etc/influxdb/influxdb.conf $(ROOTDIR)/etc/influxdb/influxdb.conf.org
	$(Q)cp -f $(COREDIR)/influxdb/influxdb.conf $(ROOTDIR)/etc/influxdb/
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/influxdb.service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/influxdb/influxdb-start-timeout.conf ./etc/systemd/system/influxdb.service.d/
