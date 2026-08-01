# CUBE SDK

include ../../build.mk

# Builds the manila service VM image -- the guest the generic driver boots to
# export a share. Required packages: python3-diskimage-builder, debootstrap,
# kpartx, qemu-img.
#
# NOTE: unlike every other openstack deliverable, manila-image-elements has no
# release branches at all -- master is the only branch upstream publishes, so
# there is no stable/2023.1 or unmaintained/2023.1 to clone and no such thing as
# an "antelope" manila service image. The elements are release-independent: the
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
MANILA_IMAGE_ELEMENTS_COMMIT := 5c2b484769d1303999b52cc0bd15b2eb3d999559

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
manila_service_image: $(BLDDIR)/manila-image-elements
	$(Q)sed -i '/^Type=oneshot$$/d' manila-image-elements/elements/manila-ssh/install.d/fetch-public-ssh-keys.service
	$(Q)cd manila-image-elements && bash -x ./bin/manila-image-create

include $(HEX_MAKEDIR)/hex_sdk.mk
