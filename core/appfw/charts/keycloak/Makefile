# CUBE SDK

include ../../../../build.mk

VERSION=17.0.1
CHART=keycloak-$(VERSION)-cube.tgz

cube.tar.gz: $(SRCDIR)/themes
	$(Q)tar -czf $@ -C $(SRCDIR)/themes/ ./cube

$(CHART): cube.tar.gz
	$(Q)helm repo add codecentric https://codecentric.github.io/helm-charts $(QEND)
	$(Q)helm fetch codecentric/keycloak --untar --untardir .chart --version $(VERSION)
	$(Q)yq -i '.version += "-cube"' .chart/keycloak/Chart.yaml
	$(Q)mkdir .chart/keycloak/data && cp -f cube.tar.gz .chart/keycloak/data/
	$(Q)cp -f $(SRCDIR)/configmap-cube-theme.yaml .chart/keycloak/templates/
	$(Q)helm package .chart/keycloak $(QEND) && rm -rf .chart


BUILD += $(CHART)
BUILDCLEAN += $(CHART)

include $(HEX_MAKEDIR)/hex_sdk.mk
