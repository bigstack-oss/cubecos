# CUBE SDK

include ../../build.mk

PROM_REPO := https://github.com/prometheus/prometheus.git
PROM_VER  := v2.55.1
PROM_SRC  := prometheus-source
PROM_BIN  := prometheus
PROM_TOOL := promtool
UI_PATH   := $(PROM_SRC)/web/ui

$(PROM_SRC):
	$(call RUN_CMD_TIMED,git clone -b $(PROM_VER) $(PROM_REPO) $(PROM_SRC),"  CLONE   $(PROM_BIN)")

$(PROM_TOOL): $(PROM_SRC)
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cd $(UI_PATH) && nvm install $(QEND)
	$(call RUN_CMD_TIMED,cd $(PROM_SRC) && \
		go get golang.org/x/crypto@v0.31.0 && \
		go mod tidy, "  UPDATE  $(PROM_BIN)")
	$(Q)cd $(UI_PATH) && nvm use $(QEND)
	$(call RUN_CMD_TIMED, cd $(PROM_SRC) && \
        make build,"  BUILD   $(PROM_BIN)")
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV

BUILD += $(PROM_TOOL)
BUILDCLEAN += $(PROM_TOOL) $(PROM_SRC)

include $(HEX_MAKEDIR)/hex_sdk.mk
