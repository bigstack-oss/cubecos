# CUBE SDK

include ../build.mk

# Additional fakeroot build tools required by this project
# SUBDIRS += fakeroot

HEAVY_PREREQ_SUBDIRS += api
HEAVY_PREREQ_SUBDIRS += ui
HEAVY_PREREQ_SUBDIRS += cubectl
HEAVY_PREREQ_SUBDIRS += phone-home-agent
HEAVY_PREREQ_SUBDIRS += appctl
HEAVY_PREREQ_SUBDIRS += lachesis
HEAVY_PREREQ_SUBDIRS += exporters
HEAVY_PREREQ_SUBDIRS += yq
HEAVY_PREREQ_SUBDIRS += etcd
HEAVY_PREREQ_SUBDIRS += terraform
HEAVY_PREREQ_SUBDIRS += docker
HEAVY_PREREQ_SUBDIRS += k3s
HEAVY_PREREQ_SUBDIRS += keycloak
HEAVY_PREREQ_SUBDIRS += rancher
HEAVY_PREREQ_SUBDIRS += appfw
SUBDIRS += $(HEAVY_PREREQ_SUBDIRS)

# Building heavy filesystem
SUBDIRS += heavyfs

# heavyfs' heavy_base needs nothing the subdirs above build (see the NOTE in
# heavyfs/Makefile), so on a clean build it runs alongside them rather than after.
# Each side stays serial on its own, and the SUBDIRS walk that follows finds both
# done. Backgrounded in the shell rather than with -j: -j would hand a jobserver to
# both sides, and holding the subdirs to one at a time under it takes -j1 sub-makes,
# each of which makes make print a warning.
# heavy_base's output goes to a file and is printed once both sides are done:
# RUN_CMD_TIMED prints its label, runs, then ends the line with the time, so two
# sides sharing the output would splice one's label onto the other's time.
# Not for RC builds, which take heavy_rootfs from the release instead.
ifeq ($(RC),)
ALL += heavy_overlap
.PHONY: heavy_overlap
heavy_overlap:
	$(Q)log=$$(mktemp /tmp/heavy_base.XXXXXX); \
	$(MAKE) -C heavyfs heavy_base_early >$$log 2>&1 & base=$$!; \
	$(MAKE) TARGET=_all_r $(HEAVY_PREREQ_SUBDIRS); subdirs=$$?; \
	wait $$base; based=$$?; cat $$log; rm -f $$log; \
	[ $$based -eq 0 ] && [ $$subdirs -eq 0 ]
endif

# SDK static/shared library
LIB_SUBDIRS += cube_sdk_library
LIB_SUBDIRS += sdk_so
SUBDIRS += $(LIB_SUBDIRS)

# mysql library
SUBDIRS += mysql

SUBDIRS += modules

# Building images
SUBDIRS += main

SUBDIRS += fixpacks

include $(HEX_MAKEDIR)/hex_sdk.mk
