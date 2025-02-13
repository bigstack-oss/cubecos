# CUBE SDK

include ../../../../build.mk

LIB = $(PROJ_LIBDIR)/libcube_sdk.a

LIB_SRCS = endpoint.cpp common.cpp

COMPILE_FOR_SHARED_LIB = 1

CPPFLAGS += -I$(TOP_SRCDIR)/core/cube_sdk_library/include

include $(HEX_MAKEDIR)/hex_sdk.mk
