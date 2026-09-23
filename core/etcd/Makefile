# CUBE SDK

include ../../build.mk

APP := etcd etcdctl
VERSION := v3.5.23

# $(GITHUB_DL_BASE), not a literal host: this is a GitHub release asset, the class throttled to
# ~40 KB/s from our build network (cubecos#1350). Defaults to https://github.com in project.mk.
ETCD_DL_URL := $(GITHUB_DL_BASE)/etcd-io/etcd/releases/download/$(VERSION)

$(APP):
	$(Q)wget -qO- --no-check-certificate $(ETCD_DL_URL)/etcd-$(VERSION)-linux-amd64.tar.gz | tar -I pigz -x --strip-components=1 --wildcards */etcd */etcdctl

install: $(APP)
	$(Q)cp -f $(APP) /usr/local/bin/

BUILD += $(APP)
BUILDCLEAN += $(APP)

include $(HEX_MAKEDIR)/hex_sdk.mk
