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
# public keys at these paths (the private halves never leave release signing);
# a build without them mints throwaway dev keypairs so the signing chain can be
# exercised end to end.
#
# Hybrid: a release must carry both an ECDSA P-384 and an ML-DSA-87 signature.
ADVISOR_PUB_PEM ?= /etc/ssl/advisor-release.pub.pem
ADVISOR_PRIV_PEM ?= /etc/ssl/advisor-release.priv.pem
ADVISOR_MLDSA_PUB_PEM ?= /etc/ssl/advisor-release-mldsa87.pub.pem
ADVISOR_MLDSA_PRIV_PEM ?= /etc/ssl/advisor-release-mldsa87.priv.pem

# Fire only when no key was injected. Must not depend on the private halves:
# a production build carries only the public keys, and a rule keyed on a
# private file would mint a fresh pair over the real anchor.
$(ADVISOR_PUB_PEM):
	$(Q)openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 -pkeyopt ec_param_enc:named_curve -out $(ADVISOR_PRIV_PEM)
	$(Q)chmod 600 $(ADVISOR_PRIV_PEM)
	$(Q)openssl pkey -in $(ADVISOR_PRIV_PEM) -pubout -out $@

# A pre-hybrid build minted a P-256 dev pair here, which advisor_key.h refuses.
# Its private half sits beside it and derives it, which a release anchor's
# cannot (that half never leaves release signing), so let the rule above mint a
# P-384 pair over it.
ifeq ($(shell openssl pkey -pubin -in $(ADVISOR_PUB_PEM) -noout -text 2>/dev/null | grep -q 'NIST CURVE: P-384' || \
	{ openssl pkey -in $(ADVISOR_PRIV_PEM) -pubout 2>/dev/null | cmp -s - $(ADVISOR_PUB_PEM) && echo stale; }),stale)
.PHONY: $(ADVISOR_PUB_PEM)
endif

$(ADVISOR_MLDSA_PUB_PEM):
	$(Q)openssl genpkey -algorithm ML-DSA-87 -out $(ADVISOR_MLDSA_PRIV_PEM)
	$(Q)chmod 600 $(ADVISOR_MLDSA_PRIV_PEM)
	$(Q)openssl pkey -in $(ADVISOR_MLDSA_PRIV_PEM) -pubout -out $@

# Refuse a key of the wrong kind (e.g. a pre-hybrid P-256 dev key).
advisor_key.h: $(ADVISOR_PUB_PEM) $(ADVISOR_MLDSA_PUB_PEM)
	$(Q)openssl pkey -pubin -in $(ADVISOR_PUB_PEM) -noout -text | grep -q 'NIST CURVE: P-384' || \
		{ echo "$(ADVISOR_PUB_PEM) is not ECDSA P-384: inject the release key, or delete it (and its private half) to mint a dev pair" >&2; exit 1; }
	$(Q)openssl pkey -pubin -in $(ADVISOR_MLDSA_PUB_PEM) -noout -text | grep -q 'ML-DSA-87' || \
		{ echo "$(ADVISOR_MLDSA_PUB_PEM) is not ML-DSA-87: inject the release key, or delete it (and its private half) to mint a dev pair" >&2; exit 1; }
	$(Q)echo "#define ADVISOR_RELEASE_PUBLIC_KEY \"$(shell cat $(ADVISOR_PUB_PEM) | awk '{printf "%s\\n", $$0}')\"" > $@
	$(Q)echo "#define ADVISOR_RELEASE_MLDSA_PUBLIC_KEY \"$(shell cat $(ADVISOR_MLDSA_PUB_PEM) | awk '{printf "%s\\n", $$0}')\"" >> $@

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

