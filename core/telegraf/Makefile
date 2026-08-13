# CUBE SDK

include ../../build.mk

CLONEDIR := telegraf
BRANCH := 1.24.4-cube
PKGNAME := telegraf-1.24.4-1.x86_64.rpm
PKG := $(CLONEDIR)/build/dist/$(PKGNAME)
BINNAME := telegraf
BIN := $(TOP_BLDDIR)/core/telegraf/telegraf/telegraf

$(CLONEDIR):
	$(call RUN_CMD_TIMED, for i in {1..3} ; do timeout 120 git clone -b $(BRANCH) https://github.com/bigstack-oss/telegraf.git $(CLONEDIR) && break ; done,"  CLONE   telegraf")

# Dependency security patches live in go.mod on the $(BRANCH) branch, not here.
$(PKG):: $(CLONEDIR)
	$(call RUN_CMD_TIMED, cd $(CLONEDIR) && make $(PKGNAME),"  GEN     $(PKGNAME)")

$(BIN):: $(CLONEDIR)
	$(call RUN_CMD_TIMED, cd $(CLONEDIR) && make,"  BUILD   $(BINNAME)")

BUILD += $(BIN)
BUILDCLEAN += $(CLONEDIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
