# CUBE

include ../../build.mk

# space delimited list of sources to exclude
EXCLUDE_SRCS :=

LIB_SRCS := $(filter-out $(EXCLUDE_SRCS), $(shell cd $(SRCDIR) && ls *.c *.cpp 2>/dev/null))

SUBDIRS := tests

# The Advisor release public key is compiled in rather than read from disk: a
# key file on a node can be replaced by any root process, which would defeat
# verification silently. Same mechanism as hex's license_key.h.
#
# Provisioned like the licence key too: the production build injects the real
# public key at this path (the private half never leaves the release CI); a
# build without one mints a throwaway dev keypair so the signing chain can be
# exercised end to end.
ADVISOR_PUB_PEM ?= /etc/ssl/advisor-release.pub.pem
ADVISOR_PRIV_PEM ?= /etc/ssl/advisor-release.priv.pem

# Fires only when no key was injected. Must not depend on the private half:
# a production build carries only the public key, and a rule keyed on the
# private file would mint a fresh pair over the real anchor.
$(ADVISOR_PUB_PEM):
	$(Q)openssl ecparam -name prime256v1 -genkey -noout -out $(ADVISOR_PRIV_PEM)
	$(Q)chmod 600 $(ADVISOR_PRIV_PEM)
	$(Q)openssl ec -in $(ADVISOR_PRIV_PEM) -pubout -out $@ 2>/dev/null

advisor_key.h: $(ADVISOR_PUB_PEM)
	$(Q)echo "#define ADVISOR_RELEASE_PUBLIC_KEY \"$(shell cat $< | awk '{printf "%s\\n", $$0}')\"" > $@

BUILD += advisor_key.h

# BUILD names the header and the objects side by side, which under -j leaves
# their order to chance. config_advisor.cpp includes the header, so say so.
config_advisor.o: advisor_key.h

CLEAN += advisor_key.h

# needed for mysql operations
CPPFLAGS += \
	-I$(TOP_SRCDIR)/hex/src/modules/ \
	-I$(COREDIR)/cube_sdk_library/include \
	-I$(COREDIR)/cube_sdk_library/src \
	-I$(COREDIR)/mysql

include $(HEX_MAKEDIR)/hex_sdk.mk

