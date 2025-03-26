# CUBE SDK

include ../../build.mk

# find a latest stable ubuntu to create. required packages: python3-diskimage-builder
$(BLDDIR)/octavia:
	$(Q)git clone -b $(OPS_GITHUB_TAG) --depth 1 https://github.com/openstack/octavia.git

haproxy_amphora_image: $(BLDDIR)/octavia
	$(Q)cd octavia/diskimage-create && bash -x ./diskimage-create.sh

include $(HEX_MAKEDIR)/hex_sdk.mk