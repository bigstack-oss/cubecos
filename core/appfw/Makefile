# CUBE SDK

include ../../build.mk

appfw.tgz:
	$(Q)$(call RUN_CMD_TIMED, \
		tar -cvzf appfw.tgz -C $(COREDIR)/appfw/core . $(QEND), \
		"  BUILD   appfw.tgz")

BUILD += appfw.tgz
BUILDCLEAN += appfw.tgz

SUBDIRS += charts

include $(HEX_MAKEDIR)/hex_sdk.mk
