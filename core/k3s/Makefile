# CUBE SDK

include ../../build.mk

include $(SRCDIR)/k3s.mk

VERSION     := v1.32.13+k3s1
K3S_REPO    := https://github.com/k3s-io/k3s.git
K3S_SRC_DIR := k3s-source

BIN := k3s
INSTALL_SCRIPT := install.sh

KUBECONFIG := /etc/rancher/k3s/k3s.yaml

define IMGS
endef
export IMGS

.dapper:
	$(Q)curl -sL https://releases.rancher.com/dapper/v0.6.0/dapper-$$(uname -s)-$$(uname -m) > .dapper.tmp
	$(Q)chmod +x .dapper.tmp
	$(Q)mv .dapper.tmp .dapper

$(K3S_SRC_DIR):
	$(call RUN_CMD_TIMED,git clone --depth 1 -b $(VERSION) $(K3S_REPO) $(K3S_SRC_DIR),"  CLONE   k3s")

# Optional base URL holding a prebuilt k3s for this version, e.g.
# https://<host>/api/v1/repositories/cubecos-build-cache-files/download. EMPTY BY DEFAULT: unset,
# the binary is built from source exactly as before, so a clean checkout needs access to nothing
# of ours. fetch-or-build.sh exits non-zero on any miss -- unset, unreachable, absent, bad
# checksum, wrong version -- and the build falls through to k3s-from-source below.
#
# Worth caching because the dapper build is the most expensive step in the whole build (4876 s in
# prod #750) and reruns every time: the jail container is recreated per build, so its podman
# storage goes with it. It is also the most fragile -- prod #146 died inside it on an Alpine apk
# fetch -- so skipping it buys reliability as well as time. See cubecos#1350.
K3S_CACHE ?=

# Only stdout is silenced when VERBOSE=0, so the probe's routine chatter obeys VERBOSE like every
# other step and leaves one labelled line on a hit. Not $(QEND), which is `>/dev/null 2>&1`: the
# script puts routine misses on stdout but anomalies (bad checksum, wrong version) on stderr, and
# dropping those turns a poisoned cache entry into a silent 81-min source build on every single
# run with nothing in the log saying why. Not RUN_CMD_TIMED either: that swallows its command's
# output into a tmpfile, which would also swallow the source build's own per-step labels on the
# fallback path below.
$(BIN):
	$(Q)K3S_CACHE="$(K3S_CACHE)" VERSION="$(VERSION)" OUT="$(CURDIR)/$(BIN)" \
		sh $(SRCDIR)/build/fetch-or-build.sh $(if $(Q),>/dev/null) \
		&& echo "  K3S     $(VERSION) restored from cache" \
		|| $(MAKE) $(BIN)-from-source

# k3s 1.32.13 pins x/net, x/crypto and x/sys with replace directives, and requires an x/text, all
# older than the releases the other Go rebuilds here take (docker.mk, influxdb.mk). Raise them in
# the clone before the build. Upstream's maintained branches still replace the same three, at newer
# versions, so the replaces are raised rather than dropped. cache-key.sh hashes these lines, so a
# change here builds a new binary instead of restoring the old one from the cache.
K3S_GO_REPLACE := golang.org/x/net=golang.org/x/net@v0.61.0 golang.org/x/crypto=golang.org/x/crypto@v0.58.0 golang.org/x/sys=golang.org/x/sys@v0.49.0
K3S_GO_GET := golang.org/x/text@v0.43.0

# k3s refuses to start unless runtime.Version() equals the UpstreamGolang it was linked with,
# which version.sh takes from kubernetes' build/dependencies.yaml (go1.24.13 for 1.32.13, a
# dead Go line). We build with a newer Go, so record the Go we actually build with, as the
# Alpine, NixOS and Yocto k3s packages do. Fail loudly if upstream moves the line.
# TAG, not DRONE_TAG: 1.32.13 takes its version from $TAG (scripts/git_version.sh), where 1.26.6
# read $DRONE_TAG; without it the binary calls itself v1.32.13+k3s-<commit>, not v1.32.13+k3s1.
.PHONY: $(BIN)-from-source
$(BIN)-from-source: $(K3S_SRC_DIR) .dapper
	$(Q)rm -rf $(K3S_SRC_DIR)/build $(K3S_SRC_DIR)/dist $(K3S_SRC_DIR)/bin
	$(Q)cp $(SRCDIR)/build/Dockerfile.dapper $(K3S_SRC_DIR)/Dockerfile.dapper
	$(Q)grep -q '^VERSION_GOLANG=' $(K3S_SRC_DIR)/scripts/version.sh
	$(Q)sed -i 's/^VERSION_GOLANG=.*/VERSION_GOLANG="$$(go version | cut -d" " -f3)"/' $(K3S_SRC_DIR)/scripts/version.sh
	$(Q)chmod +x $(K3S_SRC_DIR)/scripts/ci
	$(call RUN_CMD_TIMED,cd $(K3S_SRC_DIR) && \
		export GOTOOLCHAIN=local GOFLAGS=-mod=mod && \
		go mod edit $(addprefix -replace ,$(K3S_GO_REPLACE)) && \
		go get $(K3S_GO_GET) && \
		go mod tidy, \
		"  GOMOD   k3s")
	$(call RUN_CMD_TIMED,cd $(K3S_SRC_DIR) && \
		export PODMAN_IGNORE_CGROUPSV1_WARNING=1 \
		TAG=$(VERSION) \
		SKIP_VALIDATE=1 \
		SKIP_IMAGE=1 \
		SKIP_AIRGAP=1 && \
		mkdir -p build/data && \
		make download && \
		make, \
		"  BUILD   k3s")
	$(Q)cp $(K3S_SRC_DIR)/dist/artifacts/k3s $(BIN)

# Releases an in-place upgrade steps through on its way from v1.26.6+k3s1, what every release so
# far shipped, to VERSION: k3s upgrades one minor version at a time. Upstream release binaries,
# checked against upstream's own checksum file. k3s.mk installs them as
# $(K3S_DIR)/ladder/<version>/k3s, and that directory is the list the upgrade reads.
# $(GITHUB_DL_BASE), as in core/etcd/Makefile: GitHub release assets are throttled from our build
# network (cubecos#1350).
LADDER_VERSIONS := v1.27.16+k3s1 v1.28.15+k3s1 v1.29.15+k3s1 v1.30.14+k3s2 v1.31.14+k3s1
LADDER_DIR := ladder
K3S_DL_URL := $(GITHUB_DL_BASE)/k3s-io/k3s/releases/download

$(LADDER_DIR):
	$(call RUN_CMD_TIMED,rm -rf $@.tmp && for v in $(LADDER_VERSIONS); do \
		d=$@.tmp/$$v; mkdir -p $$d && \
		wget -q --no-check-certificate -P $$d $(K3S_DL_URL)/$$v/k3s $(K3S_DL_URL)/$$v/sha256sum-amd64.txt && \
		sum=$$(awk '$$2 == "k3s" {print $$1}' $$d/sha256sum-amd64.txt) && [ -n "$$sum" ] && \
		echo "$$sum  $$d/k3s" | sha256sum -c - && \
		rm $$d/sha256sum-amd64.txt && chmod +x $$d/k3s || exit 1; \
		done && mv $@.tmp $@,"  PULL    k3s ladder")

# The helm that ships in the image. The jail's own helm only runs the build: jail.ubi9.dockerfile
# installs whatever release get-helm-3 found the day the jail image was built. The digest is from
# helm's own helm-<ver>-linux-amd64.tar.gz.sha256sum; bump it with the version.
HELM_VERSION := v3.22.1
HELM_SHA256 := 896cf63684a42a723d61c980369d6e588330927deb13676ca0d85006dd6da0ea
HELM_TGZ := helm-$(HELM_VERSION)-linux-amd64.tar.gz

helm:
	$(call RUN_CMD_TIMED,rm -rf $@.tmp && mkdir $@.tmp && \
		wget -q -P $@.tmp https://get.helm.sh/$(HELM_TGZ) && \
		echo "$(HELM_SHA256)  $@.tmp/$(HELM_TGZ)" | sha256sum -c - && \
		tar -C $@.tmp -xzf $@.tmp/$(HELM_TGZ) linux-amd64/helm && \
		$@.tmp/linux-amd64/helm version --template '{{.Version}}' | grep -qx $(HELM_VERSION) && \
		mv $@.tmp/linux-amd64/helm $@ && rm -rf $@.tmp,"  PULL    helm $(HELM_VERSION)")

$(INSTALL_SCRIPT):
	$(call RUN_CMD_TIMED,wget https://raw.githubusercontent.com/k3s-io/k3s/$(VERSION)/install.sh,"  PULL    $(INSTALL_SCRIPT)")
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

# Stamp, not a phony recipe: a phony step re-runs on every no-change build.
SHELL_IMAGE_STAMP := shell-image.stamp
.PHONY: build-image
build-image: $(SHELL_IMAGE_STAMP)

$(SHELL_IMAGE_STAMP): $(SRCDIR)/build/buildah-image.sh
	$(call RUN_CMD_TIMED, podman image inspect localhost/bigstack/shell >/dev/null || SRCDIR=$(SRCDIR) sh -x $(SRCDIR)/build/buildah-image.sh,"  BUILD   shell image")
	$(Q)touch $@

.PHONY: copy-image
copy-image: build-image
	$(call RUN_CMD_TIMED, sh -x $(COREDIR)/docker/copy-images.sh $(shell cat $(SRCDIR)/images.txt),"  COPY    k3s image")
	$(call RUN_CMD_TIMED, sh -x $(COREDIR)/docker/copy-images.sh containers-storage:localhost/bigstack/shell,"  COPY    shell image")

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


BUILD += $(BIN) $(INSTALL_SCRIPT) $(LADDER_DIR) helm build-image
BUILDCLEAN += .dapper and $(K3S_SRC_DIR)
DISTCLEAN += $(BIN) $(INSTALL_SCRIPT) $(LADDER_DIR) helm

SUBDIRS += ingress-nginx
SUBDIRS += ceph-csi

include $(HEX_MAKEDIR)/hex_sdk.mk
