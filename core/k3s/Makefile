# CUBE SDK

include ../../build.mk

include $(SRCDIR)/k3s.mk

VERSION := v1.26.6+k3s1

BIN := k3s
INSTALL_SCRIPT := install.sh

KUBECONFIG := /etc/rancher/k3s/k3s.yaml

define IMGS
endef
export IMGS


$(BIN):
	$(call RUN_CMD_TIMED,wget https://github.com/rancher/k3s/releases/download/$(VERSION)/$(BIN),"  PULL    $(BIN)")
	$(Q)chmod +x $(BIN)

$(INSTALL_SCRIPT):
#	$(call RUN_CMD_TIMED,wget https://get.k3s.io/ -O ./$(INSTALL_SCRIPT),"  PULL    $(INSTALL_SCRIPT)")
# 	Workaround to use previos install.sh. https://github.com/k3s-io/k3s/issues/7247
	$(call RUN_CMD_TIMED,wget https://raw.githubusercontent.com/k3s-io/k3s/34617390d05dd8574a21412aeb223218c998f83a/install.sh,"  PULL    $(INSTALL_SCRIPT)")
	${Q}sed -i '/RestartSec=5s/a StandardOutput=append:/var/log/k3s.log\nStandardError=append:/var/log/k3s.log' $(INSTALL_SCRIPT)
	$(Q)chmod +x $(INSTALL_SCRIPT)

list-images:
	$(Q)curl -sL https://github.com/k3s-io/k3s/releases/download/$(VERSION)/k3s-images.txt

ingress-traefik-chart:
	$(Q)helm repo add traefik https://helm.traefik.io/traefik
	$(Q)helm pull traefik/traefik
	$(Q)helm template traefik -n traefik traefik-*.tgz --output-dir $@

gen-certs:
	$(Q)mkdir -p /var/www/certs
	$(Q)openssl req -x509 -newkey rsa:2048 -nodes -keyout /var/www/certs/server.key -out /var/www/certs/server.cert \
		-days 3650 -subj /CN=$(shell hostname) \
		-addext "subjectAltName=DNS:localhost,DNS:cube-controller,IP:127.0.0.1,IP:$(shell hostname -i)"

install: $(BIN) $(INSTALL_SCRIPT)
	$(Q)mkdir -p $(K3S_DIR)
	$(Q)cp -f $^ $(SRCDIR)/registries.yaml $(SRCDIR)/remove_node.sh $(SRCDIR)/config.toml.tmpl $(K3S_DIR)
	$(Q)make install -C ingress-nginx
	$(Q)make install -C ceph-csi

.PHONY: build-image
build-image:
	$(call RUN_CMD_TIMED, podman image inspect localhost/bigstack/shell >/dev/null || SRCDIR=$(SRCDIR) sh -x $(SRCDIR)/build/buildah-image.sh,"  BUILD   shell image")

.PHONY: copy-image
copy-image: build-image
	$(call RUN_CMD_TIMED, sh -x $(TOP_SRCDIR)/core/docker/copy-images.sh $(shell cat $(SRCDIR)/images.txt),"  COPY    k3s image")
	$(call RUN_CMD_TIMED, sh -x $(TOP_SRCDIR)/core/docker/copy-images.sh containers-storage:localhost/bigstack/shell,"  COPY    shell image")

gw-off:
	$(Q)ip route del default via 172.17.0.1 dev eth0
	$(Q)ip route add default via 172.17.0.100 dev eth0

gw-on:
	$(Q)ip route del default via 172.17.0.100 dev eth0
	$(Q)ip route add default via 172.17.0.1 dev eth0

test:: install
	$(Q)make test -C ../docker
	$(Q)make gen-certs
	$(Q)cp -f $(K3S_DIR)/$(BIN) /usr/local/bin/
	$(Q)mkdir -p /etc/rancher/k3s/ && cp -f $(K3S_DIR)/registries.yaml /etc/rancher/k3s/
	$(Q)mkdir -p /var/lib/rancher/k3s/agent/etc/containerd/ && cp -f $(K3S_DIR)/config.toml.tmpl /var/lib/rancher/k3s/agent/etc/containerd/
	$(Q)INSTALL_K3S_SKIP_DOWNLOAD=true INSTALL_K3S_SKIP_ENABLE=true INSTALL_K3S_SELINUX_WARN=true INSTALL_K3S_SKIP_SELINUX_RPM=true \
		INSTALL_K3S_EXEC="--disable=traefik --disable=servicelb --cluster-init --kubelet-arg=cgroups-per-qos=false --kubelet-arg=enforce-node-allocatable=" \
		sh -x $(K3S_DIR)/$(INSTALL_SCRIPT)
	$(Q)systemctl start k3s
	$(Q)k3s kubectl get --raw='/readyz?verbose'
	$(Q)make test -C ingress-nginx
	$(Q)k3s kubectl apply -f $(SRCDIR)/tests/

testclean::
	$(Q)[ -e /usr/local/bin/k3s-uninstall.sh ] && sh -x /usr/local/bin/k3s-uninstall.sh || true
	$(Q)rm -rf /var/www/certs
	$(Q)make testclean -C ../docker
	$(Q)podman rm -vf --all

clean:: testclean
	$(Q)rm -rf $(K3S_DIR)


BUILD += $(BIN) $(INSTALL_SCRIPT) build-image
BUILDCLEAN +=
DISTCLEAN += $(BIN) $(INSTALL_SCRIPT)

SUBDIRS += ingress-nginx
SUBDIRS += ceph-csi

include $(HEX_MAKEDIR)/hex_sdk.mk
