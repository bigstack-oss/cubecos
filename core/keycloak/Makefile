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
KEYCLOAK_DIR := /opt/keycloak/

ifneq ($(RC),)
$(LOGIN_RPM):
	$(call RUN_CMD_TIMED, \
		wget -O login.rpm https://github.com/bigstack-oss/cube-cos-ui/releases/download/cube-cos-login-v3.0.0-rc4/cube-cos-login-17.1.0-1.cddd34e.x86_64.rpm, \
		"  PULL    $(LOGIN_RPM)")
else
include version
include build_number
include keycloak_version

LOGIN_GIT_DIR := ./git
LOGIN_RPMBUILD_DIR := rpmbuild
LOGIN_TARBALL := $(LOGIN_RPMBUILD_DIR)/SOURCES/cube-cos-login-$(LOGIN_VERSION).tar.gz
LOGIN_SPEC_FILE := $(LOGIN_RPMBUILD_DIR)/SPECS/cube-cos-login.spec
LOGIN_RPM_BUILD := $(LOGIN_RPMBUILD_DIR)/RPMS/x86_64/cube-cos-login-$(LOGIN_VERSION)-1.el9.$(LOGIN_BUILD_NUMBER).x86_64.rpm

# prepare the login source code, being pulled from GitHub using the default branch
# For RC: git clone -b v3.0.0-rc4
$(LOGIN_GIT_DIR):
	$(Q)mkdir $(LOGIN_GIT_DIR)
	$(call RUN_CMD_TIMED, \
		for i in {1..10} ; do \
		timeout 30 git clone --depth 1 https://github.com/bigstack-oss/cube-cos-ui.git $(LOGIN_GIT_DIR) && break ; \
		done,\
		"  CLONE   github.com/bigstack-oss/cube-cos-ui.git")
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cd $(LOGIN_GIT_DIR) && nvm install $(QEND)
	$(Q)cd $(LOGIN_GIT_DIR) && nvm use $(QEND) && npm install -g pnpm@latest-10 $(QEND)
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV

version: $(LOGIN_GIT_DIR)
	$(Q)echo -n "LOGIN_VERSION := " > version
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cd $(LOGIN_GIT_DIR) && \
		nvm use $(QEND) && \
		node -p "require('./packages/cube-frontend-keycloak-login/package.json').version" >> ../version
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV

build_number: $(LOGIN_GIT_DIR)
	$(Q)echo -n "LOGIN_BUILD_NUMBER := " > build_number
	$(Q)cd $(LOGIN_GIT_DIR) && \
		git rev-parse --short HEAD >> ../build_number

keycloak_version: $(LOGIN_GIT_DIR)
	$(Q)echo -n "KEYCLOAK_VERSION := " > keycloak_version
	$(Q)cd $(LOGIN_GIT_DIR) && \
		head -n 1 ./packages/cube-frontend-keycloak-login/KEYCLOAK_VERSION >> ../keycloak_version

# prepare the rpm build directory
$(LOGIN_RPMBUILD_DIR):
	$(Q)mkdir $(LOGIN_RPMBUILD_DIR)
	$(Q)cd $(LOGIN_RPMBUILD_DIR) && mkdir BUILD RPMS SOURCES SPECS SRPMS

# make the source tarball
$(LOGIN_TARBALL): $(LOGIN_RPMBUILD_DIR) $(LOGIN_GIT_DIR)
	$(Q)mkdir ./source
	$(Q)cp -r $(LOGIN_GIT_DIR)/.git/ ./source/
	$(Q)cd ./source && git checkout . $(QEND)
	$(Q)sudo rm -r ./source/.git/ ./source/.github/ ./source/.husky/ ./source/.vscode/
	$(Q)tar -cvzf "cube-cos-login-$(LOGIN_VERSION).tar.gz" source $(QEND)
	$(Q)mv ./cube-cos-login-$(LOGIN_VERSION).tar.gz $(LOGIN_RPMBUILD_DIR)/SOURCES
	$(Q)rm -r ./source

# prepare the rpm spec file
$(LOGIN_SPEC_FILE): $(LOGIN_RPMBUILD_DIR) $(LOGIN_GIT_DIR)
	$(Q)cp $(LOGIN_GIT_DIR)/packages/cube-frontend-keycloak-login/cube-cos-login.spec $(LOGIN_RPMBUILD_DIR)/SPECS

# build the login rpm package
$(LOGIN_RPM_BUILD): $(LOGIN_TARBALL) $(LOGIN_SPEC_FILE)
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(call RUN_CMD_SILENT, \
		cd $(LOGIN_GIT_DIR) && \
		nvm use $(QEND) && \
		cd - && \
		rpmbuild -bb --nodeps --define "_topdir $(CURDIR)/$(LOGIN_RPMBUILD_DIR)" --define "version $(LOGIN_VERSION)" --define "build_number $(LOGIN_BUILD_NUMBER)" --define "keycloak_version $(KEYCLOAK_VERSION)" $(LOGIN_SPEC_FILE), \
		"  BUILD   cube-cos-login-$(LOGIN_VERSION)-1.el9.$(LOGIN_BUILD_NUMBER).x86_64.rpm")
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV

# move the built rpm back to the local directory
$(LOGIN_RPM): $(LOGIN_RPM_BUILD)
	$(Q)cp -f $(LOGIN_RPM_BUILD) ./login.rpm
endif

ifneq ($(RC),)
IMG_BUILD := localhost:5080/bigstack/keycloak:17.1.0
else
IMG_BUILD := localhost:5080/bigstack/keycloak:$(LOGIN_VERSION)
endif

.load-img: $(LOGIN_RPM)
	$(Q)dnf install -y ./login.rpm $(QEND)
	$(Q)podman load -i /usr/share/cube/login/keycloak-image.tar $(QEND)
	$(Q)dnf remove -y cube-cos-login $(QEND)
	$(Q)echo $(IMG_BUILD) > $@

.push-img: .load-img
	$(Q)make push-image -C $(TOP_BLDDIR)/core/docker IMG=$(shell cat .load-img) $(QEND)
	$(Q)touch $@

.PHONY: copy-image
copy-image: .load-img
	$(call RUN_CMD_TIMED, \
		sh -x $(TOP_SRCDIR)/core/keycloak/copy-images.sh containers-storage:$(shell cat .load-img) \
		,"  COPY    keycloak image")

install:: $(CHART) .push-img
	$(Q)mkdir -p $(KEYCLOAK_DIR)
	$(Q)cp -f $(SRCDIR)/chart-values.yaml $(KEYCLOAK_DIR)
	$(Q)cp -f $(CHART) $(KEYCLOAK_DIR)

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
	$(Q)rm -rf $(LOGIN_RPMBUILD_DIR)
	$(Q)rm -rf $(LOGIN_GIT_DIR)
endif

BUILD += $(CHART)
BUILDCLEAN += $(CHART) $(LOGIN_GIT_DIR) version build_number keycloak_version $(LOGIN_RPMBUILD_DIR) $(LOGIN_RPM) .load-img .push-img $(KEYCLOAK_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
