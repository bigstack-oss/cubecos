# CUBE SDK

include ../../build.mk

APP := cubectl
SRCS := $(shell find $(SRCDIR)/app/ -name "*.go")

ifneq ($(V),)
GOVERBOSE := -v
endif

TIMEOUT := 5m
ifeq ($(TAGS),itest)
TIMEOUT := 30m
endif

$(APP): $(SRCS)
	$(call RUN_CMD_TIMED, cd $(SRCDIR)/app && go mod tidy && go build $(GOVERBOSE) -o $(BLDDIR)/$(APP),"  GEN     $@")

install: $(APP)
	$(Q)cp -f $(APP) $(SRCDIR)/scripts/* /usr/local/bin/
	@# $(Q)podman image inspect localhost/cube >/dev/null 2>&1 || podman build -t cube -f $(SRCDIR)/data/cube.dockerfile
	$(Q)podman image inspect localhost/cube >/dev/null 2>&1 || TOP_SRCDIR=$(TOP_SRCDIR) TOP_BLDDIR=$(TOP_BLDDIR) sh $(SRCDIR)/build-cube-container.sh

test:: $(SRCS)
	$(Q)make install
	$(Q)make install -C ../etcd
	$(Q)make install -C ../terraform
	$(Q)make install -C ../docker
	$(Q)make install -C ../k3s
	$(Q)make install -C ../keycloak
	$(Q)make install -C ../rancher
	$(Q)cp -f $(SRCDIR)/data/hex_config.sh /usr/sbin/hex_config
	$(Q)(cd $(SRCDIR)/app/ && go test -count=1 -p=1 -timeout=$(TIMEOUT) -tags=$(TAGS) $(GOVERBOSE) $(FLAGS) -run=$(RUN) ./...)

testclean::
#	$(Q)(cd $(SRCDIR)/app/ && CLEANUP=true go test -count=1 -p=1 -timeout=$(TIMEOUT) -tags=$(TAGS) $(GOVERBOSE) -run=$(RUN) ./...)
	$(Q)podman rm --all -f && podman volume prune -f
	$(Q)rm -f /usr/sbin/hex_config

clean:: testclean
	$(Q)buildah rm --all
	$(Q)podman image rm -f localhost/cube 2>/dev/null || true
	$(Q)rm -f /usr/local/bin/$(APP) /usr/local/bin/etcdctl-cube.sh
	$(Q)rm -rf /opt/manifests/

BUILD += $(APP)
BUILDCLEAN += $(APP)

include $(HEX_MAKEDIR)/hex_sdk.mk
