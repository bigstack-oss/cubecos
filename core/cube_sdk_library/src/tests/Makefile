# CUBE SDK

include ../../../../build.mk

TESTS_LIBS = $(PROJ_LIBDIR)/libcube_sdk.a $(HEX_SDK_LIB_ARCHIVE)

# cluster.o references HexCrypto*, which pulls crypto.o out of libhex_sdk.a and
# with it the OpenSSL symbols. Same reason hex_config's own tests link it.
TESTS_LDLIBS = -lcrypto

# cluster.hpp is a private header next to the sources, not under include/.
CPPFLAGS += -I$(COREDIR)/cube_sdk_library/include
CPPFLAGS += -I$(COREDIR)/cube_sdk_library/src

include $(HEX_MAKEDIR)/hex_sdk.mk
