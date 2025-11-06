# CUBE SDK

include ../../../build.mk

SUBDIRS += config_file
SUBDIRS += openstack
SUBDIRS += utils
SUBDIRS += third_party
SUBDIRS += cubesys

LIB = $(PROJ_LIBDIR)/libcube_sdk.a

LIB_SRCS = k3s.cpp

COMPILE_FOR_SHARED_LIB = 1

CPPFLAGS += -I$(COREDIR)/cube_sdk_library/include

include $(HEX_MAKEDIR)/hex_sdk.mk
