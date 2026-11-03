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
FIXPACK_ID            ?= v3.2.0-001

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
PKGCLEAN += *.fixpack *.out *.fixpack.md5 dummy-*

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
	$(call RUN_CMD_SILENT,$(SHELL) $(HEX_SCRIPTSDIR)/makesecfixdraft $@,"  GEN     $@")
	$(Q)sed -i "s/SUPPORTED_FIRMWARES=.*/SUPPORTED_FIRMWARES=\"$(SUPPORTED_FIRMWARES)\"/" $@/fixpack.info
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
