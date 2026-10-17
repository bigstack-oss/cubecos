# CUBE SDK

include ../../build.mk

APP := etcd etcdctl
VERSION := v3.5.34

# Built from the release tag rather than taken from the release tarball: the release is built with
# a Go older than the October 2026 security release (1.27.2 / 1.26.9), and links an x/crypto older
# than its fix. The jail's Go and ETCD_GO_GET cover both, with grpc at the latest release. Return to
# the tarball on the condition core/exporters/Makefile gives. The flags and the GitSHA ldflag are
# those of etcd's own build.sh with the release's GO_LDFLAGS="-s -w". server/ and etcdctl/ are
# modules of their own, each raised before it is built. The tag is cloned shallow, and the modules
# come from proxy.golang.org, checked against sum.golang.org. The clone is not named etcd*:
# etcd.mk installs every etcd* in this directory.
ETCD_GO_GET := golang.org/x/crypto@v0.58.0 golang.org/x/net@v0.61.0 golang.org/x/text@v0.43.0 \
	google.golang.org/grpc@v1.84.0
ETCD_SRC := src-$(VERSION)

$(ETCD_SRC):
	$(call RUN_CMD_TIMED, rm -rf $@.part && \
		git clone -q --depth 1 -b $(VERSION) https://github.com/etcd-io/etcd.git $@.part && \
		mv $@.part $@,"  CLONE   etcd-$(VERSION)")

$(APP): $(ETCD_SRC) $(SRCDIR)/Makefile
	$(call RUN_CMD_TIMED, cd $(ETCD_SRC)/$(if $(filter etcd,$@),server,etcdctl) && \
		go get $(ETCD_GO_GET) && go mod tidy && \
		CGO_ENABLED=0 go build -trimpath -installsuffix=cgo \
		-ldflags "-s -w -X go.etcd.io/etcd/api/v3/version.GitSHA=$$(git rev-parse --short HEAD)" \
		-o $(CURDIR)/$@ .,"  BUILD   $@")

# etcdctl's go.mod takes server/ through a replace, so server/ is raised first, never alongside
etcdctl: | etcd

install: $(APP)
	$(Q)cp -f $(APP) /usr/local/bin/

BUILD += $(APP)
BUILDCLEAN += $(APP) $(ETCD_SRC)

include $(HEX_MAKEDIR)/hex_sdk.mk
