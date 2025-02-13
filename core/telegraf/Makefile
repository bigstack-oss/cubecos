# CUBE SDK

include ../../build.mk

CLONEDIR := telegraf
BRANCH := 1.17.2-cube
PKGNAME := telegraf-1.17.2-1.x86_64.rpm
PKG := $(CLONEDIR)/build/dist/$(PKGNAME)
BINNAME := telegraf
BIN := $(TOP_BLDDIR)/core/telegraf/telegraf/telegraf

$(CLONEDIR):
	$(call RUN_CMD_TIMED, for i in {1..10} ; do timeout 30 git clone -b $(BRANCH) https://github.com/bigstack-oss/telegraf.git $(CLONEDIR) && break ; done,"  CLONE   telegraf")

$(PKG):: $(CLONEDIR)
	$(call RUN_CMD_TIMED, cd $(CLONEDIR) && make $(PKGNAME),"  GEN     $(PKGNAME)")

$(BIN):: $(CLONEDIR)
	$(call RUN_CMD_TIMED, cd $(CLONEDIR) && make,"  BLD     $(BINNAME)")

BUILD += $(BIN)
BUILDCLEAN += $(CLONEDIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
