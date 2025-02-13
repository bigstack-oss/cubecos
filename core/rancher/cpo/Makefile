# CUBE SDK

include ../../../build.mk

CHARTS := openstack-cinder-csi-*.tgz openstack-cloud-controller-manager-*.tgz
IMG_LIST := $(shell cat $(SRCDIR)/images.txt)


# Cloud Provider Openstack
$(CHARTS):
	$(Q)helm repo add cpo https://kubernetes.github.io/cloud-provider-openstack $(QEND)
	$(Q)helm repo update $(QEND)
	$(Q)helm pull cpo/openstack-cloud-controller-manager --version "2.28.3" $(QEND)
	$(Q)helm pull cpo/openstack-cinder-csi --version "2.28.1" $(QEND)

.PHONY: copy-image
copy-image:
	$(call RUN_CMD_TIMED, \
		sh -x $(TOP_SRCDIR)/core/docker/copy-images.sh $(IMG_LIST) \
		,"  COPY    cpo image")

clean::
	$(Q)podman image rm -f $(IMG) 2>/dev/null || true


BUILD += $(CHARTS)
BUILDCLEAN += $(CHARTS)

include $(HEX_MAKEDIR)/hex_sdk.mk
