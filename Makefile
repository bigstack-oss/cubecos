ifneq (x$(DEVOPS_ENV),x__JAIL__)
include jail/cntrjail.mk
.DEFAULT_GOAL := help
else

# CUBE SDK

include build.mk

# HEX SDK
SUBDIRS += hex

# Core SDK
SUBDIRS += core

# The SUBDIRS walk builds hex/src completely (its initramfs images take ~8 minutes)
# before it enters core, but heavyfs' heavy_base -- the longest step of the build --
# needs only hex's rootfs, the SDK library and hex_crashd, which heavyfs installs
# (hex/make/hex_crashd.mk). So once those three exist, two lines run side by side:
#   - core's heavy_overlap: heavy_base alongside the components heavyfs comes after
#   - the rest of hex/src, then core's libraries, mysql and modules, then core/main's
#     programs; none of these reads heavyfs, so none of them waits for heavy_base
# The SUBDIRS walk that follows finds both lines done. The second line's output goes
# to a file and is printed afterwards, for the reason given at heavy_overlap.
# Not for RC builds, which take heavy_rootfs from the release instead.
ifeq ($(RC),)
ALL += critical_overlap
.PHONY: critical_overlap
critical_overlap:
	$(Q)$(MAKE) -C hex TARGET=_all_r fakeroot rootfs
	$(Q)$(MAKE) -C hex/src TARGET=_all_r hex_sdk_library sdk_so
	$(Q)$(MAKE) -C hex/src/hex_crashd _all
	$(Q)log=$$(mktemp /tmp/critical_overlap.XXXXXX); \
	{ $(MAKE) -C hex TARGET=_all_r src && \
	  $(MAKE) -C core TARGET=_all_r cube_sdk_library sdk_so mysql modules && \
	  $(MAKE) -C core/main _build; } >$$log 2>&1 & rest=$$!; \
	$(MAKE) -C core heavy_overlap; heavy=$$?; \
	wait $$rest; rested=$$?; cat $$log; rm -f $$log; \
	[ $$heavy -eq 0 ] && [ $$rested -eq 0 ]
endif

# Convenience targets
help::
	$(Q)echo "testhotfixes Build test hotfixes"

.PHONY: testhotfixes
testhotfixes:
	$(Q)$(MAKE) -C hex/test_hotfixes full
	$(Q)$(MAKE) -C core/main testhotfixes

help::
	$(Q)echo "usb          Build USB image"

.PHONY: usb
usb: all
	$(Q)$(MAKE) -C core/main usb

help::
	$(Q)echo "iso          Build ISO image"

# Must enable here since its not enabled by default
.PHONY: iso
iso: all
	$(Q)$(MAKE) -C core/main iso

help::
	$(Q)echo "pxedeploy    Deply image to a PXE Server"

.PHONY: pxedeploy
pxedeploy: all
	$(Q)$(MAKE) -C core/main pxe pxedeploy

help::
	$(Q)echo "pxeserver    Build PXE Server image"

.PHONY: pxeserver
pxeserver: all
	$(Q)$(MAKE) -C core/main pxe pxeserver

help::
	$(Q)echo "pxeserveriso    Build PXE Server ISO image"

.PHONY: pxeserveriso
pxeserveriso: all
	$(Q)$(MAKE) -C core/main pxe pxeserveriso

help::
	$(Q)echo "liveusb      Build live USB image"

.PHONY: liveusb
liveusb: all
	$(Q)$(MAKE) -C core/main liveusb

help::
	$(Q)echo "pxe          Build PXE image"

.PHONY: pxe
pxe: all
	$(Q)$(MAKE) -C core/main pxe

help::
	$(Q)echo "ova          Build OVA image"

.PHONY: ova vmware
ova vmware: all
	$(Q)$(MAKE) -C core/main ova

help::
	$(Q)echo "tempest_image Build the Tempest runner image for OPENSTACK_RELEASE [PUSH=1]"
	$(Q)echo "tempest_test  Run Tempest: TARGET=<vip> [SUITE=smoke|api|scenario|full|<plugin>] [REGEX=..] [CONCURRENCY=2] [OUT=dir]"
	$(Q)echo "              [PREFLIGHT=0] [MIN_FIPS=n]; ROOT_PASS defaults to Cube@<last two octets of TARGET>"
	$(Q)echo "tempest_preflight Check TARGET has what SUITE needs (cluster check, FIPs, capacity, images)"
	$(Q)echo "tempest_report Re-render the HTML report of a run: OUT=<run dir> (tempest_test writes OUT/report.html itself)"

.PHONY: tempest_image tempest_test tempest_preflight tempest_report
tempest_image tempest_test tempest_preflight tempest_report:
	$(Q)$(MAKE) -C core/tempest $@

help::
	$(Q)echo "vagrant      Build vagrant box."

.PHONY: vagrant
vagrant: all
	$(Q)$(MAKE) -C core/main vagrant

help::
	$(Q)echo "sbom         Build SBOM artifacts"

.PHONY: sbom
sbom:
	$(Q)$(MAKE) -C core/main sbom

# sums, sign, attest, verify and howtoverify (hex's projsign.mk) run in core/main, the directory
# that builds and signs the release; hex forwards them there from here, and lists them in help.
PROJ_SIGN_DIR := core/main

help::
	$(Q)echo "masqon       turn on iptables masquerade, allowing VMs to Internet"

.PHONY: masqon
masqon:
	$(Q)iptables -t nat -I POSTROUTING -o eth0 -j MASQUERADE

help::
	$(Q)echo "masqoff      turn off iptables masquerade, prohibiting VMs to Internet"

.PHONY: masqoff
masqoff:
	$(Q)iptables -t nat -F POSTROUTING

include $(HEX_MAKEDIR)/hex_sdk.mk

endif
