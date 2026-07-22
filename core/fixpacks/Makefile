# CUBE SDK

include ../../build.mk

FIRST_RELEASE_VERSION := v3.0.0-rc1
SUPPORTED_FIRMWARES   ?= 3.1.0
FIXPACK_ID            ?= v3.1.0-002

ifeq ($(COMMITSINCE),)
COMMITSINCE           := $(FIRST_RELEASE_VERSION)
endif
ifeq ($(COMMITUNTIL),)
COMMITUNTIL           := $(shell date "+%Y%m%d")
endif
FIXPACK_DRAFT         := $(COMMITSINCE)_$(COMMITUNTIL)
FIXPACK               := $(shell ls -d */ 2>/dev/null | sed "s;/;;" | xargs -i echo {}.fixpack)

BUILD    += secfix
PKGCLEAN += $(FIXPACK)* $(FIXPACK_DRAFT)* $(COMMITSINCE) secfixdraft *.out

export PROJ_GUARDED_BIN

help::
	$(Q)echo "hotfixdraft  COMMITSINCE= COMMITUNTIL= generate draft hotfix from given commit range"
	$(Q)echo "secfix       FIXPACK_ID=$(FIXPACK_ID)"

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

include $(HEX_MAKEDIR)/hex_sdk.mk
