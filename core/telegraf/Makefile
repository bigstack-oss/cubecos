# CUBE SDK

include ../../build.mk

CLONEDIR := telegraf
BRANCH := 1.17.2-cube
PKGNAME := telegraf-1.17.2-1.x86_64.rpm
PKG := $(CLONEDIR)/build/dist/$(PKGNAME)
BINNAME := telegraf
BIN := $(TOP_BLDDIR)/core/telegraf/telegraf/telegraf

$(CLONEDIR):
	$(call RUN_CMD_TIMED, for i in {1..3} ; do timeout 120 git clone -b $(BRANCH) https://github.com/bigstack-oss/telegraf.git $(CLONEDIR) && break ; done,"  CLONE   telegraf")

$(PKG):: $(CLONEDIR)
	$(call RUN_CMD_TIMED, cd $(CLONEDIR) && \
		go get golang.org/x/crypto@v0.31.0 && \
		go mod edit -replace github.com/nats-io/jwt=github.com/nats-io/jwt@v1.2.3-0.20210314221642-a826c77dc9d2 && \
		go mod tidy,"  UPDATE  $(PKGNAME)")
	$(call RUN_CMD_TIMED, cd $(CLONEDIR) && make $(PKGNAME),"  GEN     $(PKGNAME)")

$(BIN):: $(CLONEDIR)
	$(call RUN_CMD_TIMED, cd $(CLONEDIR) && \
		go get golang.org/x/crypto@v0.31.0 && \
		go mod edit -replace github.com/nats-io/jwt=github.com/nats-io/jwt@v1.2.3-0.20210314221642-a826c77dc9d2 && \
		go mod tidy,"  UPDATE  $(BINNAME)")
	$(call RUN_CMD_TIMED, cd $(CLONEDIR) && make,"  BUILD   $(BINNAME)")

BUILD += $(BIN)
BUILDCLEAN += $(CLONEDIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
