# CUBE SDK

include ../../build.mk

APP := etcd etcdctl
VERSION := v3.5.5

$(APP):
	$(Q)wget -qO- --no-check-certificate https://github.com/etcd-io/etcd/releases/download/$(VERSION)/etcd-$(VERSION)-linux-amd64.tar.gz | tar -I pigz -x --strip-components=1 --wildcards */etcd */etcdctl

install: $(APP)
	$(Q)cp -f $(APP) /usr/local/bin/

BUILD += $(APP)
BUILDCLEAN += $(APP)

include $(HEX_MAKEDIR)/hex_sdk.mk
