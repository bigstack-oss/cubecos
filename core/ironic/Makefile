# CUBE SDK

include ../../build.mk

ubuntu-1804-baremetal.qcow2:
	$(call RUN_CMD_TIMED,cd $(BLDDIR) && DIB_DEV_USER_USERNAME=cube DIB_DEV_USER_PWDLESS_SUDO=yes DIB_DEV_USER_PASSWORD=passw0rd disk-image-create ubuntu vm devuser dhcp-all-interfaces -o $@,"  BUILD   $@")

CLEAN += ubuntu-1804-baremetal.qcow2

include $(HEX_MAKEDIR)/hex_sdk.mk