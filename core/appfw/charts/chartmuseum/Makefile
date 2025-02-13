include ../../../../build.mk

VERSION=3.6.2
CHART=chartmuseum-$(VERSION).tgz

IMGS += ghcr.io/helm/chartmuseum:v0.14.0

$(CHART):
	$(Q)helm repo add chartmuseum https://chartmuseum.github.io/charts >/dev/null
	$(Q)helm fetch chartmuseum/chartmuseum --version $(VERSION)

BUILD += $(CHART)
BUILDCLEAN += $(CHART)

include $(HEX_MAKEDIR)/hex_sdk.mk
