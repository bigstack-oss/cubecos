# CUBE SDK

include ../../build.mk

# Builds the manila service VM image -- the guest the generic driver boots to
# export a share. Required packages: python3-diskimage-builder, debootstrap,
# kpartx, qemu-img. The target also bounds debootstrap's wget -- see the note by the
# manila_service_image rule.
#
# NOTE: unlike every other openstack deliverable, manila-image-elements has no
# release branches at all -- master is the only branch upstream publishes, so
# there is no stable/2024.1 or unmaintained/2024.1 to clone and no such thing as
# a "caracal" manila service image; the qcow2 is named for the release it ships
# with, not for anything in it. The elements are release-independent: the
# guest runs nfs-kernel-server and samba, not manila. Rebuilding is therefore a
# base-OS refresh, which is the point -- see the commit that added this target.
#
# bin/manila-image-create is called with no arguments on purpose. Its defaults
# are MANILA_IMG_OS=manila-ubuntu-minimal, MANILA_IMG_OS_VER=jammy and
# MANILA_SHARE_PROTO=default, and "default" is exactly the ubuntu-nfs +
# ubuntu-cifs pair config_manila.cpp asks for with
# enabled_share_protocols = NFS,CIFS. Jammy is also what the image being replaced
# already ran, so this does not move the base OS either.
#
# The checkout is pinned to a commit, not to master, because master is the only
# branch this project has: cloning it unpinned would silently change the image on
# every build and there would be no way to say which elements produced the qcow2
# on the NAS. This is the commit the shipped image was built from.
#
# NOTE: bump MANILA_IMAGE_ELEMENTS_COMMIT when the manila service image is
# refreshed, and rebuild, re-upload and re-md5 the image on the NAS in the same
# change -- the pin and the artifact have to move together.
#
# #638 moved the pin from 5c2b484 to 68a7e4be (master as of 2026-08-14) and rebuilt.
# Nothing in those seven commits reaches the elements this image is built from
# (ubuntu-nfs, ubuntu-cifs, manila-ssh, vm, manila-ubuntu-minimal,
# dhcp-all-interfaces): they add a lustre element we do not build, move
# manila-centos-minimal off yum, and touch zuul/gate tooling. bin/manila-image-create
# does change, but not in a way that reaches a zero-argument invocation -- DIB_RELEASE
# moves from before argument parsing to inside configure() (a fix for `-d centos`
# setting MANILA_IMG_OS_VER too late; MANILA_IMG_OS_VER still defaults to jammy), lustre
# joins the protocol validation, and valid_distro loses a missing-space bash bug that
# only fires with -d. So the pin now tracks upstream while the artifact is unchanged in
# substance -- the refresh comes from debootstrap picking up current jammy packages.
MANILA_IMAGE_ELEMENTS_COMMIT := 68a7e4beccbe36ca6c3c601c85aca041ddd7f326

$(BLDDIR)/manila-image-elements:
	$(Q)git clone https://github.com/openstack/manila-image-elements.git
	$(Q)cd manila-image-elements && git checkout $(MANILA_IMAGE_ELEMENTS_COMMIT)

# Upstream regression, hit for real on jim-1cc -- see the commit that added this
# target. manila-ssh ships two pieces that now deadlock each other:
#
#   install.d/99-start-ssh-after-full-boot  rewrites ssh.service to
#                                           "After=... multi-user.target"
#   install.d/fetch-public-ssh-keys.service is WantedBy=multi-user.target and,
#                                           since Sep 2025, Type=oneshot
#
# A Type=oneshot unit has to *finish* before its target is reached, so sshd now
# waits on the key fetch. That fetch curls 169.254.169.254 with no
# --connect-timeout, and the generic driver's service network has no metadata
# route, so it never returns: sshd never starts, manila cannot reach the service
# instance, and the share lands in error after max_time_to_build_instance.
# CubeCOS authenticates to the service instance with service_instance_password,
# never with a fetched key, so the fetch has nothing to contribute here anyway.
#
# Dropping Type=oneshot restores exactly the semantics of the image running in
# production today, which predates the regression.
# debootstrap fetches every .deb with a bare `wget -U "debootstrap/$$VERSION"` -- see
# fetch_url() in /usr/share/debootstrap/functions -- with no --timeout, no --tries, and
# no environment hook to pass either. One half-open connection therefore hangs the build
# forever instead of failing it: hit on jim, where a single .deb stalled 9 minutes with
# the log frozen and the process still in S state, while the same URL fetched in 1.5 s
# both directly and through squid. The stall is indistinguishable from slow progress,
# which is the expensive part.
#
# wget's only other lever is its config file, and DIB's 08-debootstrap hook runs
# `sudo sh -c 'http_proxy= no_proxy= debootstrap ...'`, so WGETRC does not survive into
# the environment that matters. /etc/wgetrc is what is left. Appended idempotently,
# keyed on `timeout` already being set, so a second build is a no-op and an operator who
# has their own timeout is not overridden.
manila_service_image: $(BLDDIR)/manila-image-elements
	$(Q)grep -qE '^[[:space:]]*timeout[[:space:]]*=' /etc/wgetrc || \
		printf '\n# added by core/manila: bound debootstrap fetches, see manila_service_image\ntimeout = 30\ntries = 3\nwaitretry = 5\n' >> /etc/wgetrc
	$(Q)sed -i '/^Type=oneshot$$/d' manila-image-elements/elements/manila-ssh/install.d/fetch-public-ssh-keys.service
	$(Q)cd manila-image-elements && bash -x ./bin/manila-image-create

include $(HEX_MAKEDIR)/hex_sdk.mk
