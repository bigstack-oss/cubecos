# CUBE SDK

include ../../../../build.mk

SUBDIRS = tests

LIB = $(PROJ_LIBDIR)/libcube_sdk.a

LIB_SRCS = config_file.cpp

COMPILE_FOR_SHARED_LIB = 1

CPPFLAGS += -I$(COREDIR)/cube_sdk_library/include

include $(HEX_MAKEDIR)/hex_sdk.mk
