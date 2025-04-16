# CUBE SDK

include ../../../../build.mk

VERSION=2.1.0
CHART=docker-registry-$(VERSION).tgz

IMGS += registry:2.7.1

$(CHART):
	$(Q)helm repo add twuni https://helm.twun.io $(QEND)
	$(Q)helm fetch twuni/docker-registry --version $(VERSION)

BUILD += $(CHART)
BUILDCLEAN += $(CHART)

include $(HEX_MAKEDIR)/hex_sdk.mk
