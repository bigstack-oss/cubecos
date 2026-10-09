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

.PHONY: tempest_image tempest_test tempest_preflight
tempest_image tempest_test tempest_preflight:
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

help::
	$(Q)echo "sums         Write the SHA256SUMS manifest of core/main's ship directory"
	$(Q)echo "sign         Sign the SHA256SUMS manifest (cosign)"
	$(Q)echo "attest       Attest the SBOM to every image that contains the rootfs (cosign)"
	$(Q)echo "verify       Check the manifest signature, the attestations and every file's digest"
	$(Q)echo "howtoverify  Write <release>_HOW_TO_VERIFY.txt for a signed release"

.PHONY: sums sign attest verify howtoverify
sums sign attest verify howtoverify:
	$(Q)$(MAKE) -C core/main $@

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
