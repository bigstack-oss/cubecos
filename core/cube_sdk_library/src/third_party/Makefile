# CUBE SDK

include ../../../../build.mk

LIB = $(PROJ_LIBDIR)/libcube_sdk.a

LIB_SRCS = json11.cpp

COMPILE_FOR_SHARED_LIB = 1

CPPFLAGS += -I$(TOP_SRCDIR)/core/cube_sdk_library/include -I$(TOP_SRCDIR)/core/cube_sdk_library/include/third_party

include $(HEX_MAKEDIR)/hex_sdk.mk
