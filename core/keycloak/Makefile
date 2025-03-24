# CUBE SDK

include ../../build.mk

# login keycloak helm chart
CHART_VERSION := 18.1.1
CHART := keycloak-$(CHART_VERSION).tgz

$(CHART):
	$(Q)helm repo add codecentric https://codecentric.github.io/helm-charts $(QEND)
	$(Q)helm pull codecentric/keycloak --version $(CHART_VERSION)

# login rpm
LOGIN_VERSION :=
LOGIN_BUILD_NUMBER :=
KEYCLOAK_VERSION :=

LOGIN_GIT_DIR := ./git
LOGIN_RPMBUILD_DIR := $(TOP_BLDDIR)/core/keycloak/rpmbuild
LOGIN_TARBALL = $(LOGIN_RPMBUILD_DIR)/SOURCES/cube-cos-login-$(LOGIN_VERSION).tar.gz
LOGIN_SPEC_FILE := $(LOGIN_RPMBUILD_DIR)/SPECS/cube-cos-login.spec
LOGIN_RPM_BUILD = $(LOGIN_RPMBUILD_DIR)/RPMS/x86_64/cube-cos-login-$(LOGIN_VERSION)-1.el9.$(LOGIN_BUILD_NUMBER).x86_64.rpm
LOGIN_RPM := $(TOP_BLDDIR)/core/keycloak/login.rpm
IMG_BUILD = localhost:5080/bigstack/keycloak:$(LOGIN_VERSION)

KEYCLOAK_DIR := /opt/keycloak/

# prepare the login source code, being pulled from GitHub using the default branch
$(LOGIN_GIT_DIR):
	$(Q)mkdir $(LOGIN_GIT_DIR)
	$(call RUN_CMD_TIMED, \
		for i in {1..10} ; do \
		timeout 30 git clone --depth 1 https://github.com/bigstack-oss/cube-cos-ui.git $(LOGIN_GIT_DIR) && break ; \
		done,\
		"  CLONE   github.com/bigstack-oss/cube-cos-ui.git")
	$(Q)$(eval LOGIN_VERSION=`cd $(LOGIN_GIT_DIR) && node -p "require('./packages/cube-frontend-keycloak-login/package.json').version"`)
	$(Q)$(eval LOGIN_BUILD_NUMBER=`cd $(LOGIN_GIT_DIR) && git rev-parse --short HEAD`)
	$(Q)$(eval KEYCLOAK_VERSION=`cd $(LOGIN_GIT_DIR) && head -n 1 ./packages/cube-frontend-keycloak-login/KEYCLOAK_VERSION`)

# prepare the rpm build directory
$(LOGIN_RPMBUILD_DIR):
	$(Q)mkdir $(LOGIN_RPMBUILD_DIR)
	$(Q)cd $(LOGIN_RPMBUILD_DIR) && mkdir BUILD RPMS SOURCES SPECS SRPMS

# make the source tarball
$(LOGIN_TARBALL): $(LOGIN_RPMBUILD_DIR) $(LOGIN_GIT_DIR)
	$(Q)mkdir ./source
	$(Q)mkdir -p ./source/packages/cube-frontend-ui-library
	$(Q)cp -r \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-ui-library/src \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-ui-library/package.json \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-ui-library/postcss.config.js \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-ui-library/tailwind.config.js \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-ui-library/tsconfig.json \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-ui-library/vite.config.ts \
		./source/packages/cube-frontend-ui-library
	$(Q)mkdir -p ./source/packages/cube-frontend-ui-theme
	$(Q)cp -r \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-ui-theme/src \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-ui-theme/package.json \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-ui-theme/tsconfig.json \
		./source/packages/cube-frontend-ui-theme
	$(Q)mkdir -p ./source/packages/cube-frontend-utils
	$(Q)cp -r \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-utils/src \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-utils/package.json \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-utils/tsconfig.json \
		./source/packages/cube-frontend-utils
	$(Q)mkdir -p ./source/packages/cube-frontend-keycloak-login
	$(Q)cp -r \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-keycloak-login/public \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-keycloak-login/rollup-plugins \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-keycloak-login/src \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-keycloak-login/index.html \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-keycloak-login/package.json \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-keycloak-login/postcss.config.js \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-keycloak-login/tailwind.config.js \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-keycloak-login/tsconfig.app.json \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-keycloak-login/tsconfig.json \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-keycloak-login/tsconfig.node.json \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-keycloak-login/vite.config.ts \
		./source/packages/cube-frontend-keycloak-login
	$(Q)mkdir -p ./source/packages/cube-frontend-keycloak-login/keycloak
	$(Q)cp -r \
		$(LOGIN_GIT_DIR)/packages/cube-frontend-keycloak-login/keycloak/themes \
		./source/packages/cube-frontend-keycloak-login/keycloak
	$(Q)cp -r \
		$(LOGIN_GIT_DIR)/LICENSE \
		$(LOGIN_GIT_DIR)/package.json \
		$(LOGIN_GIT_DIR)/pnpm-lock.yaml \
		$(LOGIN_GIT_DIR)/pnpm-workspace.yaml \
		$(LOGIN_GIT_DIR)/tsconfig.json \
		./source
	$(Q)tar -cvzf "cube-cos-login-$(LOGIN_VERSION).tar.gz" source 2>&1 > /dev/null
	$(Q)mv ./cube-cos-login-$(LOGIN_VERSION).tar.gz $(LOGIN_RPMBUILD_DIR)/SOURCES
	$(Q)rm -r ./source

# prepare the rpm spec file
$(LOGIN_SPEC_FILE): $(LOGIN_RPMBUILD_DIR) $(LOGIN_GIT_DIR)
	$(Q)cp $(LOGIN_GIT_DIR)/packages/cube-frontend-keycloak-login/cube-cos-login.spec $(LOGIN_RPMBUILD_DIR)/SPECS

# build the login rpm package
$(LOGIN_RPM_BUILD): $(LOGIN_TARBALL) $(LOGIN_SPEC_FILE)
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(call RUN_CMD_TIMED, \
		nvm use $(UI_NODE_VERSION) && \
		rpmbuild -bb --nodeps --define "_topdir $(LOGIN_RPMBUILD_DIR)" --define "version $(LOGIN_VERSION)" --define "build_number $(LOGIN_BUILD_NUMBER)" --define "keycloak_version $(KEYCLOAK_VERSION)" $(LOGIN_SPEC_FILE), \
		"  BUILD   cube-cos-login-$(LOGIN_VERSION)-1.el9.$(LOGIN_BUILD_NUMBER).x86_64.rpm")
	$(Q)# disable nvm
	$(Q)sed -i 's/^/#/g' $$BASH_ENV

# move the built rpm back to the local directory, and clean up the build environment
$(LOGIN_RPM): $(LOGIN_RPM_BUILD)
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cp -f $(LOGIN_RPM_BUILD) ./login.rpm
	$(Q)# disable nvm
	$(Q)sed -i 's/^/#/g' $$BASH_ENV

.load-img: $(LOGIN_RPM)
	$(Q)dnf install -y ./login.rpm
	$(Q)podman load -i /usr/share/cube/login/keycloak-image.tar
	$(Q)echo $(IMG_BUILD) > $@

.push-img: .load-img
	$(Q)make push-image -C $(TOP_BLDDIR)/core/docker IMG=$(shell cat .load-img)
	$(Q)dnf remove -y cube-cos-login
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
	$(Q)helm --kubeconfig /etc/rancher/k3s/k3s.yaml uninstall keycloak -n keycloak 2>/dev/null || true
	$(Q)k3s kubectl delete ns keycloak 2>/dev/null || true
	$(Q)podman rm -if keycloak >/dev/null
	$(Q)podman rm -if mysql >/dev/null

clean:: testclean
	$(Q)podman image rm -f $(shell cat .load-img) 2>/dev/null || true
	$(Q)rm -rf $(LOGIN_RPMBUILD_DIR)
	$(Q)rm -rf $(LOGIN_GIT_DIR)

BUILD += $(CHART) .push-img
BUILDCLEAN += $(CHART) $(LOGIN_GIT_DIR) $(LOGIN_RPMBUILD_DIR) $(LOGIN_RPM) .load-img .push-img $(KEYCLOAK_DIR)

include $(HEX_MAKEDIR)/hex_sdk.mk
