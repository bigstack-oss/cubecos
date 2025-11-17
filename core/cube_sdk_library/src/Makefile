# CUBE SDK

include ../../../build.mk

SUBDIRS += config_file
SUBDIRS += openstack
SUBDIRS += utils
SUBDIRS += third_party
SUBDIRS += cubesys

LIB = $(PROJ_LIBDIR)/libcube_sdk.a

LIB_SRCS = cluster.cpp
LIB_SRCS += filesystem.cpp
LIB_SRCS += helm.cpp
LIB_SRCS += http.cpp
LIB_SRCS += k3s.cpp
LIB_SRCS += terraform.cpp
LIB_SRCS += upgrade.cpp
LIB_SRCS += url.cpp

COMPILE_FOR_SHARED_LIB = 1

CPPFLAGS += -I$(COREDIR)/cube_sdk_library/include

include $(HEX_MAKEDIR)/hex_sdk.mk
