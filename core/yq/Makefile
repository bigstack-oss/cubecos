# Cube SDK

include ../../build.mk

YQ_REPO    := https://github.com/mikefarah/yq.git
YQ_VER     := v4.45.1
YQ_SRC_DIR := yq-source
YQ_BIN     := yq

$(YQ_SRC_DIR):
	$(call RUN_CMD_TIMED,git clone -b $(YQ_VER) $(YQ_REPO) $(YQ_SRC_DIR),"  CLONE   yq")

$(YQ_BIN): $(YQ_SRC_DIR)
	$(call RUN_CMD_TIMED,cd $(YQ_SRC_DIR) && go mod tidy,"  UPDATE  yq")
	$(call RUN_CMD_TIMED,cd $(YQ_SRC_DIR) && \
		CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		go build \
		-ldflags="-s -w" \
		-o ../$(YQ_BIN) ., \
		"  BUILD   yq")

BUILD += $(YQ_BIN)
BUILDCLEAN += $(YQ_BIN) $(YQ_SRC_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
