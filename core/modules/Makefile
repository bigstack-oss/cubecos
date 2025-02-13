# CUBE

include ../../build.mk

# space delimited list of sources to exclude
EXCLUDE_SRCS :=

LIB_SRCS := $(filter-out $(EXCLUDE_SRCS), $(shell cd $(SRCDIR) && ls *.c *.cpp 2>/dev/null))

SUBDIRS := tests

# needed for mysql operations
CPPFLAGS += -I$(TOP_SRCDIR)/hex/src/modules/ -I$(TOP_SRCDIR)/core/cube_sdk_library/include -I$(TOP_SRCDIR)/core/mysql

include $(HEX_MAKEDIR)/hex_sdk.mk

