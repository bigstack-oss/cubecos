ifneq (x$(DEVOPS_ENV),x__JAIL__)
include jail/cntrjail.mk
ifneq (,$(wildcard */jenkins/jenkins.mk))
include */jenkins/jenkins.mk
endif
.DEFAULT_GOAL := help

.PHONY: help
help::
	$(Q)echo "PROJECT=XXXX centos9-jail     Create CentOS9 jail"
	$(Q)echo "PROJECT=XXXX enter            Configure and enter jail"
	$(Q)echo "clean-all-cntr                Clean all running containers"
	$(Q)echo "clean-dangling-img            Clean all dangling docker images"
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
	$(Q)echo "vagrant      Build vagrant box."

.PHONY: vagrant
vagrant: all
	$(Q)$(MAKE) -C core/main vagrant

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
