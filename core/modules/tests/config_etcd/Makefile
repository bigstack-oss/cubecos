# HEX SDK

include ../../../../build.mk

hex_config_LIBS = $(PROJ_LIBDIR)/libcube_sdk.a

TESTS_EXTRA_PROGRAMS = hex_config

hex_config_MODULES = config_dummies.o config_etcd.o

CPPFLAGS += -I$(TOP_SRCDIR)/core/modules -I$(TOP_SRCDIR)/hex/src/modules/include -I$(TOP_SRCDIR)/core/cube_sdk_library/include

include $(HEX_MAKEDIR)/hex_sdk.mk
