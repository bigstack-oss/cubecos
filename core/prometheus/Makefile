
# CUBE SDK

include ../../build.mk

PROM_REPO := https://github.com/prometheus/prometheus.git
PROM_VER  := v2.55.1
PROM_SRC  := prometheus-source
PROM_TOOL := promtool

$(PROM_SRC):
	$(call RUN_CMD_TIMED,git clone -b $(PROM_VER) $(PROM_REPO) $(PROM_SRC),"  CLONE   prometheus")

$(PROM_TOOL): $(PROM_SRC)
	$(call RUN_CMD_TIMED,cd $(PROM_SRC) && \
		CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		go build \
		-ldflags="-s -w -X github.com/prometheus/common/version.Version=$(PROM_VER)" \
		-o ../$(PROM_TOOL) ./cmd/promtool, \
		"  BUILD   promtool")

prometheus: $(PROM_TOOL)

BUILD += prometheus
BUILDCLEAN += prometheus

include $(HEX_MAKEDIR)/hex_sdk.mk
