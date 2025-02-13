# HEX SDK

include ../../../build.mk

# space delimited list of dirs to exclude
EXCLUDE_DIRS := config_etcd

# Exclude deleted source directories that contain broken symlinks to Makefiles
EXCLUDE_DIRS += $(shell find -L * -name Makefile -type l 2>/dev/null | xargs dirname 2>/dev/null)

# List subdirs excluding 'EXCLUDE_DIRS' and folder name ends with '_deleted'
SUBDIRS := $(filter-out $(EXCLUDE_DIRS), $(shell find * -type d ! -name \*_deleted -prune 2>/dev/null))

include $(HEX_MAKEDIR)/hex_sdk.mk
