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
# does change, and one of those changes *does* reach a zero-argument invocation: ff78b8cb
# drops `debootstrap` from need_required_packages() for rhel/centos, and
# verify_dependencies() runs on every invocation regardless of arguments, so upstream no
# longer offers to install it on a build host like this one. That is why the rule below
# asserts it rather than only naming it above. The rest does not reach us: DIB_RELEASE
# moves from before argument parsing to inside configure() (a fix for `-d centos` setting
# MANILA_IMG_OS_VER too late -- it still defaults to jammy either way), lustre joins the
# protocol validation, `yum` becomes `dnf` in a branch where el9's yum is already a dnf
# symlink, and valid_distro loses a missing-space bash bug that only fires with -d. So the
# pin tracks upstream while the artifact is unchanged in substance -- the refresh comes
# from debootstrap picking up current jammy packages.
MANILA_IMAGE_ELEMENTS_COMMIT := 68a7e4beccbe36ca6c3c601c85aca041ddd7f326

# The checkout is keyed on the SHA, not on the directory.
#
# This used to be a bare `$(BLDDIR)/manila-image-elements:` rule, and a directory target is
# up to date the moment it exists -- so on any warm build dir the whole rule was skipped,
# `git checkout` never ran, and a bumped pin silently rebuilt the *old* elements. #638 was
# the first time this pin had ever moved, and the tree had to be removed by hand for the
# new SHA to take effect. A stamp named after the SHA makes the bump the thing that
# invalidates the clone. Both the stamp and the clone are relative, so they live in
# core/manila's own build dir beside each other rather than at the top of the tree.
#
# It re-clones rather than fetch+checkout on purpose, and that matters for the `sed` below:
# on a warm tree the line it deletes is already gone, so `grep -c Type=oneshot` reads 0
# whether or not the workaround fired and it can no longer be proven to have applied. A
# pristine tree makes 1 -> 0 checkable.
MANILA_ELEMENTS_DIR := manila-image-elements
MANILA_ELEMENTS_REPO := https://github.com/openstack/manila-image-elements.git
MANILA_ELEMENTS_STAMP := manila-elements-$(MANILA_IMAGE_ELEMENTS_COMMIT).stamp

$(MANILA_ELEMENTS_STAMP):
	$(Q)rm -f manila-elements-*.stamp
	$(Q)rm -rf $(MANILA_ELEMENTS_DIR)
	$(call RUN_CMD_TIMED,git clone $(MANILA_ELEMENTS_REPO) $(MANILA_ELEMENTS_DIR),"  CLONE   manila-image-elements")
	$(Q)cd $(MANILA_ELEMENTS_DIR) && git checkout $(MANILA_IMAGE_ELEMENTS_COMMIT)
	$(Q)touch $@

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
# wget's only other lever is its config file. DIB's 08-debootstrap hook runs
# `sudo sh -c 'http_proxy= no_proxy= debootstrap ...'`, so WGETRC does not survive into the
# environment that matters -- but ~/.wgetrc does: this sudoers has `always_set_home`, so
# HOME is /root inside that shell, and wget reads ~/.wgetrc at *higher* precedence than
# /etc/wgetrc. Verified on the jim jail, with a deliberately bogus directive:
#
#   $$ sudo sh -c "http_proxy= no_proxy= wget --version"
#   wget: Unknown command 'bogusdirective' in /root/.wgetrc at line 1.
#
# So this writes root's own dotfile rather than a system config file. Because ~/.wgetrc
# wins over /etc/wgetrc, the guard checks *both* -- an operator who has set a timeout
# system-wide is not silently overridden -- and a second build is a no-op either way.
manila_service_image: $(MANILA_ELEMENTS_STAMP)
	$(Q)# upstream ff78b8cb dropped debootstrap from need_required_packages() for
	$(Q)# rhel/centos, so verify_dependencies() no longer installs it on this build host.
	$(Q)command -v debootstrap >/dev/null || \
		{ echo "manila_service_image: debootstrap missing, and upstream no longer installs it on rhel/centos -- dnf install debootstrap" >&2; exit 1; }
	$(Q)grep -qhE '^[[:space:]]*timeout[[:space:]]*=' /root/.wgetrc /etc/wgetrc 2>/dev/null || \
		printf '\n# added by core/manila: bound debootstrap fetches, see manila_service_image\ntimeout = 30\ntries = 3\nwaitretry = 5\n' >> /root/.wgetrc
	$(Q)sed -i '/^Type=oneshot$$/d' manila-image-elements/elements/manila-ssh/install.d/fetch-public-ssh-keys.service
	$(Q)cd manila-image-elements && bash -x ./bin/manila-image-create

.PHONY: manila_service_image

include $(HEX_MAKEDIR)/hex_sdk.mk
