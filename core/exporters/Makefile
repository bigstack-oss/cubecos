# CUBE SDK

include ../../build.mk

# Prometheus exporters, built from source at the upstream release tag.
#
# Built here rather than in exporters.mk so the artifacts land in the build tree like every
# other component's, and a rootfs install is a copy rather than a download.
#
# Provenance is deliberate -- these run as daemons on every node. All but one are the
# prometheus or prometheus-community org; apache_exporter is the exporter the official
# prometheus.io catalogue lists for Apache and has no org-backed alternative. See
# exporters.mk for the per-exporter reasoning.
#
# Source rather than the release tarballs (or, for node_exporter, EPEL's node-exporter rpm) only
# to clear scanner findings (cubecos#978). Every High and Critical finding on what 3.2.0 shipped
# sits in the Go standard library, x/crypto, x/net or x/text, and no release is yet built with
# the October 2026 Go security release (1.27.2 / 1.26.9). The jail's Go and EXPORTER_GO_GET
# cover both halves. Return an exporter to its upstream artifact once `go version -m` on it
# shows go >= 1.27.2, x/net >= 0.60.0, x/text >= 0.41.0 and x/crypto >= 0.56.0.
BLACKBOX_VER := 0.29.0
IPMI_VER := 1.10.1
MEMCACHED_VER := 0.17.0
APACHE_VER := 1.1.1
NODE_VER := 1.12.1

EXPORTER_GO_GET := golang.org/x/crypto@v0.58.0 golang.org/x/net@v0.61.0 golang.org/x/text@v0.43.0
EXPORTER_VERSION_PKG := github.com/prometheus/common/version
# $(1) version. Run in the clone, so git rev-parse names the tag's commit.
EXPORTER_LDFLAGS = -s -w -X $(EXPORTER_VERSION_PKG).Version=$(1) \
	-X $(EXPORTER_VERSION_PKG).Revision=$$(git rev-parse HEAD) -X $(EXPORTER_VERSION_PKG).Branch=HEAD

# $(1) binary name, $(2) version, $(3) GitHub org/repo, $(4) package to build, $(5) extra go build
# flags. The flags and the version ldflags are upstream's own, from each tag's .promu.yml. The
# release tag is cloned shallow: git clone is not the GitHub surface that is throttled from our
# build network (cubecos#1350), and the modules come from proxy.golang.org, checked against
# sum.golang.org.
define exporter_build
$$(TOP_BLDDIR)/core/exporters/$(1)-$(2)-src:
	$$(call RUN_CMD_TIMED, rm -rf $$@.part && \
		git clone -q --depth 1 -b v$(2) https://github.com/$(3).git $$@.part && \
		mv $$@.part $$@,"  CLONE   $(1)-$(2)")

$$(TOP_BLDDIR)/core/exporters/$(1): $$(TOP_BLDDIR)/core/exporters/$(1)-$(2)-src
	$$(call RUN_CMD_TIMED, cd $$< && go get $$(EXPORTER_GO_GET) && go mod tidy && \
		CGO_ENABLED=0 go build $(5) -ldflags "$$(call EXPORTER_LDFLAGS,$(2))" -o $$@ $(4), \
		"  BUILD   $(1)")

BUILD += $$(TOP_BLDDIR)/core/exporters/$(1)
BUILDCLEAN += $$(TOP_BLDDIR)/core/exporters/$(1) $$(TOP_BLDDIR)/core/exporters/$(1)-$(2)-src
endef

$(eval $(call exporter_build,blackbox_exporter,$(BLACKBOX_VER),prometheus/blackbox_exporter,.,))
$(eval $(call exporter_build,ipmi_exporter,$(IPMI_VER),prometheus-community/ipmi_exporter,.,-a -tags 'netgo static_build'))
$(eval $(call exporter_build,memcached_exporter,$(MEMCACHED_VER),prometheus/memcached_exporter,./cmd/memcached_exporter,))
$(eval $(call exporter_build,apache_exporter,$(APACHE_VER),Lusitaniae/apache_exporter,.,-a -tags netgo))
$(eval $(call exporter_build,node_exporter,$(NODE_VER),prometheus/node_exporter,.,))

include $(HEX_MAKEDIR)/hex_sdk.mk
