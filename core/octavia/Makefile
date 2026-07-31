# CUBE SDK

include ../../build.mk

# Builds the amphora VM image. Required packages: python3-diskimage-builder.
# diskimage-create.sh is called with no arguments on purpose: it then takes the
# upstream defaults for the branch cloned below, which is how the base OS is
# chosen. For 2023.1 that default is ubuntu-minimal/jammy -- the same base OS
# the current image already uses, so this hop does not move it.
#
# NOTE: the branch is NEXT_OPS_GITHUB_BRANCH_02 (unmaintained/2023.1), not
# BRANCH_01 (stable/2023.1). Antelope is past its maintained window and the
# GitHub mirror has deleted the stable/2023.1 branch entirely -- cloning it
# fails with "Remote branch not found", which does not point back here.
$(BLDDIR)/octavia:
	$(Q)git clone -b $(NEXT_OPS_GITHUB_BRANCH_02) --depth 1 https://github.com/openstack/octavia.git

haproxy_amphora_image: $(BLDDIR)/octavia
	$(Q)cd octavia/diskimage-create && bash -x ./diskimage-create.sh

include $(HEX_MAKEDIR)/hex_sdk.mk