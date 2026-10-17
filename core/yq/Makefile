# Cube SDK

include ../../build.mk

YQ_REPO    := https://github.com/mikefarah/yq.git
YQ_VER     := v4.45.1
YQ_SRC_DIR := yq-source
YQ_BIN     := yq

$(YQ_SRC_DIR):
	$(call RUN_CMD_TIMED,git clone -b $(YQ_VER) $(YQ_REPO) $(YQ_SRC_DIR),"  CLONE   yq")

# Built from source only to clear scanner findings (cubecos#978). Raises x/net and x/text past
# the Go 2026-10 security release's fixes; return to upstream's yq_linux_amd64 once a release is
# built with go >= 1.27.2 and x/net >= 0.60.0 (v4.54.1 is go1.27.1, x/net 0.59.0).
$(YQ_BIN): $(YQ_SRC_DIR)
	$(call RUN_CMD_TIMED,cd $(YQ_SRC_DIR) && go get golang.org/x/net@v0.61.0 golang.org/x/text@v0.43.0 && go mod tidy,"  UPDATE  yq")
	$(call RUN_CMD_TIMED,cd $(YQ_SRC_DIR) && \
		CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		go build \
		-ldflags="-s -w" \
		-o ../$(YQ_BIN) ., \
		"  BUILD   yq")

BUILD += $(YQ_BIN)
BUILDCLEAN += $(YQ_BIN) $(YQ_SRC_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
