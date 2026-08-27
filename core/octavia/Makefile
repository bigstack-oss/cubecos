# CUBE SDK

include ../../build.mk

# Builds the amphora VM image -- the guest that carries octavia's data plane.
# Required packages: python3-diskimage-builder.
#
# The checkout is pinned to the octavia release tag the controllers run, not to a
# branch. Two reasons:
#
#   - the amphora agent inside the image and the controller outside it speak a
#     versioned REST API, so they have to be one release. That release is decided by
#     core/octavia/octavia.mk, which is why OCTAVIA_VER is read out of it below
#     rather than restated here -- one pin, and no way for the two to drift.
#   - a branch is a moving target. #1206 cloned OPS_GITHUB_BRANCH_02 and had to,
#     because the GitHub mirror deletes stable/<release> once a release leaves its
#     maintained window: stable/2024.1 is already gone, exactly as stable/2023.1
#     was, and the resulting "Remote branch not found" does not point back here. A
#     tag never disappears and never moves.
#
# diskimage-create.sh is called with only -o on purpose: everything else takes the
# upstream defaults for the tag cloned above, which is how the base OS is chosen.
# For 2024.1 that default is still ubuntu-minimal/jammy -- the same base OS the
# antelope image already used -- so this hop does not move it. What changes inside
# the image is the amphora agent, from octavia 12.0.x to 14.0.x.
#
# NOTE: bump OCTAVIA_VER in core/octavia/octavia.mk when octavia moves, then rebuild,
# re-upload and re-md5 the image on the NAS in the same change -- the pin and the
# artifact have to move together, the way core/manila's do.
OCTAVIA_VER := $(shell sed -n 's/^OCTAVIA_VER := //p' $(COREDIR)/octavia/octavia.mk)

# The amphora also builds octavia-lib from source (see the note on the build rule), and
# that one is not versioned with octavia -- 3.5.0 is caracal's. Read from the same
# constraint file the venv install resolves it under, so the guest and the controllers
# agree on it for the same reason and without a second pin to remember.
OCTAVIA_LIB_VER := $(shell sed -n 's/^octavia-lib===//p' $(CARACAL_OPENSTACK_PIP_CONSTRAINT))

# Everything this Makefile reads or writes is anchored at $(TOP_BLDDIR), never at the
# directory make happens to be standing in. Make's CURDIR and hex's own BLDDIR (which
# is `$(shell pwd)`) both name the invocation directory, so with either of them
# `make -C core haproxy_amphora_image` and `make -C core/octavia haproxy_amphora_image`
# clone, build and write the image to different places. COREDIR is not the answer
# either -- it is $(TOP_SRCDIR)/core, the *source* tree, and a 344 MB qcow2 does not
# belong in a git working tree. Same shape core/extpacks/Makefile already uses for
# MAIN_DIR and NAS.
OCTAVIA_BLDDIR := $(TOP_BLDDIR)/core/octavia

# The artifact core/extpacks/Makefile copies off the NAS, named for the release it
# ships with the way the manila service and rancher cluster images are. Written
# here rather than renamed by hand after the fact, so the name is part of the build.
#
# The .md5 sidecar is the *bare hash*, i.e. `md5sum <file> | awk '{print $$1}'`:
# core/extpacks/Makefile diffs its NAS copy byte for byte against a file it produces
# the same way, so a full-format `md5sum` line never matches and silently re-copies
# ~340 MB over NFS on every build.
AMPHORA_IMAGE := $(OCTAVIA_BLDDIR)/amphora-x64-haproxy_$(CARACAL_OPENSTACK_RELEASE).qcow2

# The checkout is keyed on the tag, not on the directory.
#
# This used to be a bare `$(BLDDIR)/octavia:` rule, and a directory target is up to
# date the moment it exists -- so on any warm build dir the whole rule was skipped,
# the clone never re-ran, and a bumped pin silently rebuilt the *old* source. A stamp
# named after the tag makes the bump the thing that invalidates the clone. The stamp
# and the clone sit in core/octavia's own build dir beside the image, named absolutely
# so they land there whichever directory make was invoked from.
OCTAVIA_SRC_DIR := $(OCTAVIA_BLDDIR)/octavia
OCTAVIA_REPO := https://github.com/openstack/octavia.git
# opendev, not the GitHub mirror: this is only ever handed to `git ls-remote`, and it
# has to name the same remote the element itself clones from so the SHA it resolves is
# the one DIB will look for in its cache.
OCTAVIA_LIB_REPO := https://opendev.org/openstack/octavia-lib
OCTAVIA_SRC_STAMP := $(OCTAVIA_BLDDIR)/octavia-$(OCTAVIA_VER).stamp

$(OCTAVIA_SRC_STAMP):
	$(Q)[ -n "$(OCTAVIA_VER)" ] || \
		{ echo "octavia: OCTAVIA_VER not found in $(COREDIR)/octavia/octavia.mk" >&2; exit 1; }
	$(Q)mkdir -p $(OCTAVIA_BLDDIR)
	$(Q)rm -f $(OCTAVIA_BLDDIR)/octavia-*.stamp
	$(Q)rm -rf $(OCTAVIA_SRC_DIR)
	$(call RUN_CMD_TIMED,git clone -b $(OCTAVIA_VER) --depth 1 $(OCTAVIA_REPO) $(OCTAVIA_SRC_DIR),"  CLONE   octavia $(OCTAVIA_VER)")
	$(Q)touch $@

# The two build-host preconditions core/manila's image target already documents.
# They are not manila-specific: both images are ubuntu-minimal/jammy, so both go
# through DIB's 08-debootstrap hook and hit the same two things.
#
#   debootstrap  upstream diskimage-builder dropped it from need_required_packages()
#                for rhel/centos (manila-image-elements' ff78b8cb did the same), so
#                verify_dependencies() no longer offers to install it on a build host
#                like this one and 08-debootstrap dies with "command not found" some
#                way into the run. Asserted up front instead. Hit for real on jim.
#
#   wgetrc       debootstrap fetches every .deb with a bare `wget -U debootstrap/...`
#                -- see fetch_url() in /usr/share/debootstrap/functions -- with no
#                --timeout, no --tries and no environment hook to pass either, so one
#                half-open connection hangs the build forever instead of failing it.
#                Its only other lever is its config file, and ~/.wgetrc is the copy
#                that survives DIB's `sudo sh -c 'http_proxy= no_proxy= debootstrap'`
#                (this sudoers has always_set_home, and ~/.wgetrc outranks
#                /etc/wgetrc). The guard reads *both* so an operator who set a
#                timeout system-wide is not silently overridden, and a second build
#                is a no-op either way.
haproxy_amphora_image: $(OCTAVIA_SRC_STAMP)
	$(Q)[ -n "$(OCTAVIA_LIB_VER)" ] || \
		{ echo "haproxy_amphora_image: no octavia-lib=== pin in $(CARACAL_OPENSTACK_PIP_CONSTRAINT); without it DIB falls back to the element's dead stable/2024.1" >&2; exit 1; }
	$(Q)command -v debootstrap >/dev/null || \
		{ echo "haproxy_amphora_image: debootstrap missing, and upstream no longer installs it on rhel/centos -- dnf install debootstrap" >&2; exit 1; }
	$(Q)grep -qhE '^[[:space:]]*timeout[[:space:]]*=' /root/.wgetrc /etc/wgetrc 2>/dev/null || \
		printf '\n# added by core/octavia: bound debootstrap fetches, see haproxy_amphora_image\ntimeout = 30\ntries = 3\nwaitretry = 5\n' >> /root/.wgetrc
	$(Q)rm -f $(AMPHORA_IMAGE) $(AMPHORA_IMAGE).md5
	$(Q)# The amphora agent is installed *from source* inside the guest, and the ref
	$(Q)# it is cloned at is not the tag cloned above -- it comes from the element's
	$(Q)# own elements/amphora-agent/source-repository-amphora-agent, which at 14.0.2
	$(Q)# still names `stable/2024.1`. That branch no longer exists on opendev either
	$(Q)# (2024.1 is EOM; only unmaintained/2024.1 and the tags remain), so the build
	$(Q)# dies mid-run with "Failed to find reference to stable/2024.1" -- a stale
	$(Q)# string upstream never refreshed when the branch was deleted, and one that
	$(Q)# does not point back here.
	$(Q)#
	$(Q)# DIB_REPOREF_<repo> overrides that ref, so the agent is built from the same
	$(Q)# commit the controllers run rather than from a moving branch. Set in the
	$(Q)# environment rather than with diskimage-create.sh's -g, because -g *also*
	$(Q)# rewrites DIB_REPOLOCATION_upper_constraints to
	$(Q)# .../requirements/raw/branch/<arg>/upper-constraints.txt -- a branch path,
	$(Q)# which neither a tag nor a SHA is. Left unset, the element's own default
	$(Q)# (releases.openstack.org/constraints/upper/2024.1) is correct and stable.
	$(Q)#
	$(Q)# The *commit*, not the tag name: DIB's 98-source-repositories fetches with
	$(Q)# `+$$REPOREF:$$REPOREF` and then `$$REPOREF:fetch_$$REPOREF`, i.e. it writes
	$(Q)# the ref under refs/heads/, and an annotated tag cannot go there -- it fails
	$(Q)# with "fetching ref refs/heads/14.0.2 failed: invalid new value provided".
	$(Q)# A SHA1 can, which is the case DIB's own fallback is written for. It is
	$(Q)# derived from the clone above rather than pinned separately, so OCTAVIA_VER
	$(Q)# stays the single pin.
	$(Q)#
	$(Q)# elements/octavia-lib is in the same sequence and carries the identical stale
	$(Q)# ref, so it needs the same treatment -- but not the same value: octavia-lib
	$(Q)# is versioned 3.x independently of octavia, so it is resolved from its own
	$(Q)# pin. Both tags are annotated, and `ls-remote <tag>^{} <tag>` prints the
	$(Q)# peeled commit last when it is, or the commit alone when it is not, so the
	$(Q)# last line is the commit either way.
	$(Q)cd $(OCTAVIA_SRC_DIR)/diskimage-create && \
		DIB_REPOREF_amphora_agent=$$(git -C $(OCTAVIA_SRC_DIR) rev-parse HEAD) \
		DIB_REPOREF_octavia_lib=$$(git ls-remote $(OCTAVIA_LIB_REPO) \
			'refs/tags/$(OCTAVIA_LIB_VER)^{}' 'refs/tags/$(OCTAVIA_LIB_VER)' \
			| sed -n '$$p' | cut -f1) \
		bash -x ./diskimage-create.sh -o $(AMPHORA_IMAGE)
	$(Q)md5sum $(AMPHORA_IMAGE) | awk '{print $$1}' > $(AMPHORA_IMAGE).md5
	$(Q)echo "  AMPHORA $(notdir $(AMPHORA_IMAGE)) ($$(cat $(AMPHORA_IMAGE).md5))"

.PHONY: haproxy_amphora_image

include $(HEX_MAKEDIR)/hex_sdk.mk
