# HEX SDK

include ../../../../build.mk

hex_config_LIBS = $(PROJ_LIBDIR)/libcube_sdk.a $(PROJ_LIBDIR)/libmysql_util.a

TESTS_EXTRA_PROGRAMS = hex_config

hex_config_MODULES = config_dummies.o config_manila.o

CPPFLAGS += -I$(COREDIR)/modules -I$(TOP_SRCDIR)/hex/src/modules/include -I$(COREDIR)/cube_sdk_library/include -I$(COREDIR)/cube_sdk_library/src -I$(COREDIR)/mysql

include $(HEX_MAKEDIR)/hex_sdk.mk
