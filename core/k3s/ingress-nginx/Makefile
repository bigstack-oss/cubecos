# CUBE SDK

include ../../../build.mk

INGRESS_NGINX_DIR := /opt/k3s/ingress-nginx

VERSION := 4.15.1
CHART := ingress-nginx-$(VERSION).tgz

IMG := registry.k8s.io/ingress-nginx/controller
IMG_TAG := v1.15.1
IMG_DIGEST := sha256:594ceea76b01c592858f803f9ff4d2cb40542cae2060410b2c95f75907d659e1

$(CHART):
	$(Q)helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx $(QEND)
	$(Q)helm repo update $(QEND)
	$(Q)helm pull ingress-nginx/ingress-nginx --version $(VERSION)

.copy-img:
	$(Q)make copy-image -C $(TOP_BLDDIR)/core/docker IMG=$(IMG)@$(IMG_DIGEST)
	$(Q)touch $@

install: $(CHART) .copy-img
	$(Q)mkdir -p $(INGRESS_NGINX_DIR)
	$(Q)cp -f $(CHART) $(SRCDIR)/chart-values.yaml $(INGRESS_NGINX_DIR)/

test:: install
	$(Q)helm --kubeconfig /etc/rancher/k3s/k3s.yaml upgrade --install ingress-nginx $(CHART) \
            -n ingress-nginx  --create-namespace --wait --wait-for-jobs -f $(SRCDIR)/chart-values.yaml

BUILD += $(CHART) .copy-img
BUILDCLEAN += $(CHART) .copy-img

include $(HEX_MAKEDIR)/hex_sdk.mk
