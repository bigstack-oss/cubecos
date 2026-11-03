# CUBE SDK

include ../../build.mk

FIRST_RELEASE_VERSION := v3.0.0-rc1

# The release this tree builds. core/main/Makefile is the one place it is set, and it stamps
# the same value into the image as sys.product.version, which is what a fixpack install checks
# SUPPORTED_FIRMWARES against. A CUSTOM_beta build carries PRE_RELEASE_VERSION instead.
CUBE_MAIN_MAKEFILE    := $(TOP_SRCDIR)/core/main/Makefile
ifeq ($(CUSTOM_beta),1)
CURRENT_RELEASE       := $(shell sed -n 's/^PRE_RELEASE_VERSION *:= *//p' $(CUBE_MAIN_MAKEFILE))
else
CURRENT_RELEASE       := $(shell sed -n 's/^RELEASE_VERSION *:= *//p' $(CUBE_MAIN_MAKEFILE))
endif
ifeq ($(CURRENT_RELEASE),)
$(error Could not read the release version from $(CUBE_MAIN_MAKEFILE))
endif
SUPPORTED_FIRMWARES   ?= $(CURRENT_RELEASE)
# The kernel fixpack also serves the earlier releases. Its scripts (secfix/) handle both ways of
# installing: per node on 3.2.0+, cluster-wide through git on 3.0.0-3.1.20.
SECFIX_FIRMWARES      ?= $(CURRENT_RELEASE) 3.1.20 3.1.10 3.1.0 3.0.0
# secfix: name it by the kernel it carries and the release it is for, e.g. kernel-7.2.11-1-v3.2.0-000
# for kernel 7.2.11-1.el9.x86_64. KER_VER and KER_REL come from hex/make/kernel_definitions.mk;
# $(basename) drops the dist tag (1.el9 -> 1). fixpack.info still names the full kernel.
FIXPACK_ID            ?= kernel-$(KER_VER)-$(basename $(KER_REL))-v$(CURRENT_RELEASE)-000

ifeq ($(COMMITSINCE),)
COMMITSINCE           := $(FIRST_RELEASE_VERSION)
endif
ifeq ($(COMMITUNTIL),)
COMMITUNTIL           := $(shell date "+%Y%m%d")
endif
FIXPACK_DRAFT         := $(COMMITSINCE)_$(COMMITUNTIL)
FIXPACK               := $(filter-out dummy-%,$(shell ls -d */ 2>/dev/null | sed "s;/;;" | xargs -i echo {}.fixpack))

# QA dummy fixpacks (bigstack-oss/cubecos#2223), built with every image and locked to its release
# (CURRENT_RELEASE, never a SUPPORTED_FIRMWARES override: they belong to this build).
# norollback: no rollback, reboot required. rollback: rollback allowed, no reboot. The release is
# in the name (= the ID), so a dummy installed under one release never blocks the next one's.
DUMMY_NOROLLBACK      := dummy-norollback-v$(CURRENT_RELEASE)
DUMMY_ROLLBACK        := dummy-rollback-v$(CURRENT_RELEASE)
DUMMY_FIXPACKS        := $(DUMMY_NOROLLBACK).fixpack $(DUMMY_ROLLBACK).fixpack

BUILD    += secfix
BUILD    += dummyfix
PKGCLEAN += *.fixpack *.out *.fixpack.md5 dummy-* secfixdraft

export PROJ_GUARDED_BIN

help::
	$(Q)echo "hotfixdraft  COMMITSINCE= COMMITUNTIL= generate draft hotfix from given commit range"
	$(Q)echo "secfix       FIXPACK_ID=$(FIXPACK_ID)"
	$(Q)echo "dummyfix     QA dummy fixpacks: $(DUMMY_FIXPACKS)"

$(FIXPACK_DRAFT):
	$(call RUN_CMD_SILENT,$(SHELL) $(HEX_SCRIPTSDIR)/makehotfixdraft $@,"  GEN     $@")
	$(Q)sed -i "s/SUPPORTED_FIRMWARES=.*/SUPPORTED_FIRMWARES=\"$(SUPPORTED_FIRMWARES)\"/" $@/fixpack.info
	$(Q)sed -i "s/^exit 0.*//"                                         $@/post_install.sh
	$(Q)echo "chmod 4755 /usr/sbin/hex_{config,cli,firsttime}" >>$@/post_install.sh
	$(Q)echo "exit 0"                                                >>$@/post_install.sh
	$(Q)( cd $(TOP_BLDDIR)/core/main/rootfs/ && rsync -avr --relative root/.bashrc $(BLDDIR)/$@/rootfs/ )
	$(Q)echo "root/.bashrc"                                          >>$@/backup.lst

hotfixdraft: $(FIXPACK_DRAFT)
	$(Q)mv $< `echo $< | cut -d"_" -f1`

$(FIXPACK):
	$(call RUN_CMD,$(SHELL) $(HEX_SCRIPTSDIR)/makehotfix -C $(subst .fixpack,,$@) $@,"  GEN     $@")

fixpack: $(FIXPACK)
	$(Q)true

secfixdraft:
	$(Q)mkdir -p $@ && cp -r $(SRCDIR)/secfix/. $@/     # makesecfixdraft keeps scripts already there
	$(call RUN_CMD_SILENT,$(SHELL) $(HEX_SCRIPTSDIR)/makesecfixdraft $@,"  GEN     $@")
	$(Q)sed -i "s/SUPPORTED_FIRMWARES=.*/SUPPORTED_FIRMWARES=\"$(SECFIX_FIRMWARES)\"/" $@/fixpack.info
	$(Q)sed -i "s/FIXPACK_ID=.*/FIXPACK_ID=\"$(FIXPACK_ID)\"/" $@/fixpack.info
	$(Q)sed -i "s/FIXPACK_NAME=.*/FIXPACK_NAME=\"$(FIXPACK_ID)\"/" $@/fixpack.info
	$(call RUN_CMD,$(SHELL) $(HEX_SCRIPTSDIR)/makehotfix -C -p 20M $@ $(FIXPACK_ID).fixpack,"  GEN     $@ $(FIXPACK_ID).fixpack")
	$(Q)md5sum $(FIXPACK_ID).fixpack >$(FIXPACK_ID).fixpack.md5

secfix: secfixdraft
	$(Q)true

$(DUMMY_NOROLLBACK).fixpack: DUMMY_OPTS := no yes
$(DUMMY_ROLLBACK).fixpack: DUMMY_OPTS := yes no
$(DUMMY_FIXPACKS): %.fixpack: $(SRCDIR)/mkdummyfix.sh $(CUBE_MAIN_MAKEFILE)
	$(Q)$(SHELL) $(SRCDIR)/mkdummyfix.sh $* $* $(CURRENT_RELEASE) $(DUMMY_OPTS)
	$(call RUN_CMD,$(SHELL) $(HEX_SCRIPTSDIR)/makehotfix -C $* $@,"  GEN     $@")
	$(Q)md5sum $@ >$@.md5

dummyfix: $(DUMMY_FIXPACKS)
	$(Q)true

include $(HEX_MAKEDIR)/hex_sdk.mk
