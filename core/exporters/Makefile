# CUBE SDK

include ../../build.mk

# Prometheus exporter release tarballs.
#
# Fetched and verified here rather than in exporters.mk so the artifacts land in the build
# tree like every other component's, and a rootfs install is a copy rather than a download.
# node_exporter is not here: EPEL packages it, so exporters.mk takes it through ROOTFS_DNF.
#
# Provenance is deliberate -- these run as daemons on every node. All but one are the
# prometheus or prometheus-community org; apache_exporter is the exporter the official
# prometheus.io catalogue lists for Apache and has no org-backed alternative. See
# exporters.mk for the per-exporter reasoning.
BLACKBOX_VER := 0.28.0
IPMI_VER := 1.10.1
MEMCACHED_VER := 0.17.0
APACHE_VER := 1.1.1

BLACKBOX_URL := https://github.com/prometheus/blackbox_exporter/releases/download/v$(BLACKBOX_VER)
IPMI_URL := https://github.com/prometheus-community/ipmi_exporter/releases/download/v$(IPMI_VER)
MEMCACHED_URL := https://github.com/prometheus/memcached_exporter/releases/download/v$(MEMCACHED_VER)
APACHE_URL := https://github.com/Lusitaniae/apache_exporter/releases/download/v$(APACHE_VER)

# $(1) binary/tarball basename, $(2) version, $(3) release download base url
#
# None of these publish a detached signature, only a sha256sums.txt covering the whole
# release and served from the same host as the tarball. That is weaker than a cross-host
# KEYS -- it does not prove who built the object -- but it is what upstream offers, and it
# still catches a truncated or swapped download. Fetch to .part and rename only once the
# digest matches, so a bad object is never left where the next run would unpack it.
define exporter_build
$$(TOP_BLDDIR)/core/exporters/$(1)-$(2).linux-amd64.tar.gz:
	$$(call RUN_CMD_TIMED, mkdir -p $$(@D) && \
		wget -q $(3)/$(1)-$(2).linux-amd64.tar.gz -O $$@.part && \
		wget -qO- $(3)/sha256sums.txt | grep " $(1)-$(2).linux-amd64.tar.gz$$$$" | \
			sed "s#$(1)-$(2).linux-amd64.tar.gz#$$@.part#" | sha256sum -c - > /dev/null && \
		mv $$@.part $$@,"  FETCH   $(1)-$(2)")

$$(TOP_BLDDIR)/core/exporters/$(1): $$(TOP_BLDDIR)/core/exporters/$(1)-$(2).linux-amd64.tar.gz
	$$(call RUN_CMD_TIMED, tar -I pigz -xf $$< --directory $$(@D) \
		--strip-components 1 --wildcards '*/$(1)',"  UNPACK  $(1)")

BUILD += $$(TOP_BLDDIR)/core/exporters/$(1)
BUILDCLEAN += $$(TOP_BLDDIR)/core/exporters/$(1) \
	$$(TOP_BLDDIR)/core/exporters/$(1)-$(2).linux-amd64.tar.gz
endef

$(eval $(call exporter_build,blackbox_exporter,$(BLACKBOX_VER),$(BLACKBOX_URL)))
$(eval $(call exporter_build,ipmi_exporter,$(IPMI_VER),$(IPMI_URL)))
$(eval $(call exporter_build,memcached_exporter,$(MEMCACHED_VER),$(MEMCACHED_URL)))
$(eval $(call exporter_build,apache_exporter,$(APACHE_VER),$(APACHE_URL)))

include $(HEX_MAKEDIR)/hex_sdk.mk
