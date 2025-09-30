# CUBE SDK

include ../../build.mk

FIRST_RELEASE_VERSION := v3.0.0-rc1
SUPPORTED_FIRMWARES   := 3.0.0 3.1.0

ifeq ($(COMMITSINCE),)
COMMITSINCE           := $(FIRST_RELEASE_VERSION)
endif
ifeq ($(COMMITUNTIL),)
COMMITUNTIL           := $(shell date "+%Y%m%d")
endif
FIXPACK_DRAFT         := $(COMMITSINCE)_$(COMMITUNTIL)
FIXPACK               := $(shell ls -d */ | sed "s;/;;").fixpack

PKGCLEAN += $(FIXPACK)* $(FIXPACK_DRAFT)* $(COMMITSINCE)

export PROJ_GUARDED_BIN

help::
	$(Q)echo "hotfixdraft  COMMITSINCE= COMMITUNTIL= generate draft hotfix from given commit range"

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

include $(HEX_MAKEDIR)/hex_sdk.mk
