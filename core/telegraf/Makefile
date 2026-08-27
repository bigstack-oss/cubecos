# CUBE SDK

include ../../build.mk

CLONEDIR := telegraf
# Upstream release tag, cloned straight from influxdata. The bigstack-oss/telegraf fork
# is no longer in the build: after the sflow openstack patch was reverted its only delta
# over upstream was a golang.org/x/crypto pin, and at 1.30.3 that pin buys nothing --
# govulncheck reports the identical advisory set with and without it (cubecos#647).
TAG := v1.30.3
BINNAME := telegraf
BIN := $(TOP_BLDDIR)/core/telegraf/telegraf/telegraf

# --depth 1 keeps the clone inside the 120s timeout: upstream carries the full history the
# fork had been stripped of. The tag itself has to land in the clone, not just its commit,
# because telegraf's own Makefile derives the version it stamps into the binary from
# `git describe --exact-match --tags` and falls back to a build_version.txt+sha string.
$(CLONEDIR):
	$(call RUN_CMD_TIMED, for i in {1..3} ; do timeout 120 git clone --depth 1 -b $(TAG) https://github.com/influxdata/telegraf.git $(CLONEDIR) && break ; done,"  CLONE   telegraf")

# Built here rather than taken from the rpm telegraf.mk downloads, and that is a security
# decision, not a leftover: upstream ships 1.30.3 built with go1.22.3, and rebuilding the
# same source with the jail's current toolchain drops it from 127 known advisories to 66.
$(BIN):: $(CLONEDIR)
	$(call RUN_CMD_TIMED, cd $(CLONEDIR) && make,"  BUILD   $(BINNAME)")

BUILD += $(BIN)
BUILDCLEAN += $(CLONEDIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
