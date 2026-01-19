# CUBE SDK

include ../../build.mk

# login keycloak helm chart
CHART_VERSION := 18.1.1
CHART := keycloak-$(CHART_VERSION).tgz

$(CHART):
	$(Q)helm repo add codecentric https://codecentric.github.io/helm-charts $(QEND)
	$(Q)helm pull codecentric/keycloak --version $(CHART_VERSION)

# login rpm
LOGIN_RPM := login.rpm
KEYCLOAK_DIR := /opt/keycloak
PKG_NAME := cube-cos-login
GITHUB_URL := https://github.com/bigstack-oss/cube-cos-ui

ifneq ($(RC),)
$(LOGIN_RPM):
	$(call RUN_CMD_TIMED, \
		wget -O login.rpm $(GITHUB_URL)/releases/download/$(PKG_NAME)-v3.1.0-rc1/$(PKG_NAME)-17.2.0-1.96de32d.x86_64.rpm, \
		"  PULL    $(LOGIN_RPM)")
else
GIT_DIR := git
RPMBUILD_DIR := rpmbuild
RPMBUILD_SPECS := $(RPMBUILD_DIR)/SPECS
RPMBUILD_SOURCES := $(RPMBUILD_DIR)/SOURCES
RPMBUILD_RPMS = $(RPMBUILD_DIR)/RPMS

# prepare the login source code, being pulled from GitHub using the default branch
# For RC: git clone -b v3.1.0-rc1
$(GIT_DIR):
	$(call RUN_CMD_TIMED, \
		for i in {1..10} ; do \
		rm -fr $@ && timeout 30 git clone --depth 1 $(GITHUB_URL).git $@ && break ; \
		done,\
		"  CLONE   $(GITHUB_URL)")
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cd $@ && nvm install $(QEND)
	$(Q)cd $@ && nvm use $(QEND) && npm install -g pnpm@latest-10 $(QEND)
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV

version: $(GIT_DIR)
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cd $(GIT_DIR) && \
		nvm use $(QEND) && \
		node -p "require('./packages/cube-frontend-keycloak-login/package.json').version" >> ../version
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV

build_number: $(GIT_DIR)
	$(Q)cd $(GIT_DIR) && \
		git rev-parse --short HEAD >> ../build_number

keycloak_version: $(GIT_DIR)
	$(Q)cd $(GIT_DIR) && \
		head -n 1 ./packages/cube-frontend-keycloak-login/KEYCLOAK_VERSION >> ../keycloak_version

# prepare the rpm build directory
$(RPMBUILD_DIR):
	$(Q)mkdir $(RPMBUILD_DIR)
	$(Q)cd $(RPMBUILD_DIR) && mkdir BUILD SRPMS SPECS

# make the source tarball
$(RPMBUILD_SOURCES): $(RPMBUILD_DIR) $(GIT_DIR) version
	$(Q)mkdir ./source
	$(Q)cp -r $(GIT_DIR)/.git/ ./source/
	$(Q)cd ./source && git checkout . $(QEND)
	$(Q)sudo rm -r ./source/.git/ ./source/.github/ ./source/.husky/ ./source/.vscode/
	$(Q)tar -cvzf $@.tgz source $(QEND)
	$(Q)mkdir -p $(RPMBUILD_DIR)/SOURCES
	$(Q)mv $@.tgz $(RPMBUILD_DIR)/SOURCES/$(PKG_NAME)-`cat version`.tar.gz
	$(Q)rm -r ./source

# build the login rpm package
$(RPMBUILD_RPMS): $(RPMBUILD_SOURCES) build_number keycloak_version
	$(Q)cp $(GIT_DIR)/packages/cube-frontend-keycloak-login/$(PKG_NAME).spec $(RPMBUILD_DIR)/SPECS/
	$(Q)mkdir -p $(RPMBUILD_DIR)/RPMS/x86_64
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(call RUN_CMD_SILENT, \
		cd $(GIT_DIR) && \
		nvm use $(QEND) && \
		cd - && \
		rpmbuild -bb --nodeps --define "_topdir $(CURDIR)/$(RPMBUILD_DIR)" --define "version `cat version`" --define "build_number `cat build_number`" --define "keycloak_version `cat keycloak_version`" $(RPMBUILD_DIR)/SPECS/$(PKG_NAME).spec, \
		"  BUILD   $(PKG_NAME)-`cat version`-1.el9.`cat build_number`.x86_64.rpm")
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV
	$(Q)touch $@

# move the built rpm back to the local directory
$(LOGIN_RPM): $(RPMBUILD_RPMS)
	$(Q)cp -f $</x86_64/$(PKG_NAME)-`cat version`-1.el9.`cat build_number`.x86_64.rpm $@
endif

ifneq ($(RC),)
IMG_BUILD := localhost:5080/bigstack/keycloak:17.1.0
else
IMG_BUILD := localhost:5080/bigstack/keycloak:`cat version`
endif

.load-img: $(LOGIN_RPM)
	$(Q)dnf install -y $< $(QEND)
	$(Q)podman load -i /usr/share/cube/login/keycloak-image.tar $(QEND)
	$(Q)dnf remove -y $(PKG_NAME) $(QEND)
	$(Q)echo $(IMG_BUILD) > $@

.push-img: .load-img
	$(Q)make push-image -C $(TOP_BLDDIR)/core/docker IMG=$(shell cat $<) $(QEND)
	$(Q)touch $@

.PHONY: copy-image
copy-image: .load-img
	$(call RUN_CMD_TIMED, \
		sh -x $(COREDIR)/keycloak/copy-images.sh containers-storage:$(shell cat $<) \
		,"  COPY    keycloak image")

install:: $(CHART) .push-img
	$(Q)mkdir -p $(KEYCLOAK_DIR)
	$(Q)cp -f $(SRCDIR)/chart-values.yaml $(KEYCLOAK_DIR)/
	$(Q)cp -f $(CHART) $(KEYCLOAK_DIR)/

test:: install
ifeq ($(DEP),1)
	$(Q)make test -C $(TOP_BLDDIR)/core/k3s
endif
	$(Q)podman run -d -p 3306:3306 --name=mysql \
		-e MYSQL_ALLOW_EMPTY_PASSWORD=true \
		-e MYSQL_DATABASE=keycloak \
		-e MYSQL_USER=keycloak \
		-e MYSQL_PASSWORD=password \
		docker.io/library/mariadb:10.3.27
	$(Q)helm --kubeconfig /etc/rancher/k3s/k3s.yaml upgrade --install keycloak $(KEYCLOAK_DIR)/$(CHART) \
		-n keycloak --create-namespace --wait --wait-for-jobs -f $(KEYCLOAK_DIR)/chart-values.yaml

test-podman:: .load-img
	$(Q)podman run -d -p 80:8080 -p 443:8443 --name=keycloak \
		-e KEYCLOAK_USER=admin \
		-e KEYCLOAK_PASSWORD=admin \
		-e KEYCLOAK_DEFAULT_THEME=cube \
		$(shell cat .load-img)
	$(Q)echo Accessing keycloak on http://$(shell cat /etc/hosts | grep $$(cat /etc/hostname) | awk '{print $$1}')/auth/

testclean::
ifeq ($(DEP),1)
	$(Q)make testclean -C $(TOP_BLDDIR)/core/k3s
endif
	$(Q)helm --kubeconfig /etc/rancher/k3s/k3s.yaml uninstall keycloak -n keycloak $(QEND) || true
	$(Q)k3s kubectl delete ns keycloak $(QEND) || true
	$(Q)podman rm -if keycloak $(QEND)
	$(Q)podman rm -if mysql $(QEND)

clean:: testclean
	$(Q)podman image rm -f $(shell cat .load-img) $(QEND) || true
ifeq ($(RC),)
	$(Q)rm -rf $(RPMBUILD_DIR)
	$(Q)rm -rf $(GIT_DIR)
endif

BUILD += $(CHART)
BUILDCLEAN += $(CHART) $(GIT_DIR) version build_number keycloak_version $(RPMBUILD_DIR) $(LOGIN_RPM) .load-img .push-img $(KEYCLOAK_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk

