# Cube SDK
# cube-cos-driver binaries, built from bigstack-oss/cube-cos-driver (default
# branch): phone-home-agent (installer preflight + first-boot snapshot apply)
# and the driver server (SPA + snapshot generator + deploy orchestrator, shipped
# in the pxeserver image). Deps resolved at build time only (Go proxy + npm).

include ../../build.mk

APP := phone-home-agent
SRV := cube-cos-driver
GITHUB_URL := https://github.com/bigstack-oss/cube-cos-driver
GIT_DIR := git

ifneq ($(V),)
GOVERBOSE := -v
endif

# Clone the source (retry, shallow, default branch). Init only the first-level
# UI-lib submodule — its own nested submodules are SSH-URL and not needed.
$(GIT_DIR):
	$(call RUN_CMD_TIMED, \
		for i in 1 2 3 ; do \
		rm -fr $@ && timeout 300 git clone --depth 1 $(GITHUB_URL).git $@ && \
		(cd $@ && git submodule update --init --depth 1 external/cube-cos-ui) && break ; \
		done, \
		"  CLONE   $(GITHUB_URL)")

# Build the static agent binary (deps resolved via the Go module proxy).
$(APP): $(GIT_DIR)
	$(call RUN_CMD_TIMED, \
		cd $(GIT_DIR) && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		go build -trimpath -ldflags '-s -w' $(GOVERBOSE) \
		-o $(BLDDIR)/$(APP) ./cmd/phone-home-agent, \
		"  GEN     $(APP)")

# Build the server (SPA via Node 24 + pnpm, embedded into the Go binary).
$(SRV): $(GIT_DIR)
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cd $(GIT_DIR) && nvm install 24 $(QEND)
	$(Q)cd $(GIT_DIR) && nvm use 24 $(QEND) && npm install -g pnpm@latest-10 $(QEND)
	$(call RUN_CMD_TIMED, \
		cd $(GIT_DIR) && nvm use 24 $(QEND) && make all $(QEND) && \
		cp -f bin/$(SRV) $(BLDDIR)/$(SRV), \
		"  GEN     $(SRV)")
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV

BUILD += $(APP) $(SRV)
BUILDCLEAN += $(APP) $(SRV)
CLEAN += $(GIT_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
