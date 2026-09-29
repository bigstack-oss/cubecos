# Cube SDK
# swift installation

# install the swift client inside the epoxy virtual environment.
# note: the pypi package is python-swiftclient; the "swift" package is the
# swift *server*, which CubeCOS does not ship (ceph rgw serves object-store --
# config_swift.cpp:145-147 points all three endpoints at rgw's 8888, and
# config_swift.cpp:163-165 the s3 service's at the same port).
#
# #669 moves the client from the caracal venv to the epoxy one, the way #642 moved it
# from antelope to caracal. There is still no server to move, so the client and the
# /usr/bin/swift symlink below are the whole of it.
#
# The install is a re-declaration rather than a first install. cinder.mk runs ahead
# of this file in HEAVY_COMPONENTS and, since #655, installs cinder into the epoxy venv
# without --no-deps; cinder declares python-swiftclient, so the ===4.7.1 pinned in
# os-epoxy-pip-upper-constraints.txt:104 is already installed by the time this file
# runs. heat, python-heatclient and python-troveclient (heat.mk) and horizon
# (horizon.mk) declare it there too. Naming it here keeps the object-store client
# an explicit part of the object-store story rather than an accident of other
# components' dependency sets -- the same reason it was named in the antelope and
# caracal venvs.
#
# 4.7.1 is the stable/2025.1 release that makes --debug truncate X-Auth-Token and
# X-Storage-Token the way --info always did (upstream 437cd55a, LP #2061011 and
# #2061012); --debug-with-secrets prints them, as --debug used to. With 4.6.0's
# transaction IDs in more error messages, that is all that changes from 4.5.0 for an
# operator.
#
# The library consumers are why the CLI belongs in this venv. cinder's backup driver is
# SwiftBackupDriver both for the `cube-swift` backup type (config_cinder.cpp:669-670)
# and by default (config_cinder.cpp:690-691), and heat's OS::Swift::Container goes
# through the same library; cinder moved to the epoxy venv in #655 and heat in #661.
# Left in caracal, a bare "swift" would have been a different client from the one
# cinder-backup and heat-engine import.
#
# The caracal venv had kept a 4.5.0 of its own for the served horizon (24.0.2, whose
# Object Store panel imports swiftclient) and python-heatclient, which stayed there
# next to /usr/bin/openstack. #662 took all three to the epoxy venv, so a fresh build's
# caracal venv holds no python-swiftclient at all, and horizon's panel imports this
# file's 4.7.1.
#
# History, in case the paths below read as over-specified: the pip-installed yoga copy
# that owned /usr/local/bin/swift -- which precedes /usr/bin on PATH -- went away in
# #609, and the python3-swiftclient rpm left with the rpms that required it, as #642
# found. Nothing else owns /usr/bin/swift, so the symlink below creates it, and a bare
# "swift" resolves to it.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(NEXT_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-swiftclient==4.7.1"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries. Nothing else owns this path, and it wins PATH (see above), so
	$(Q)# a bare "swift" is epoxy 4.7.1.
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/swift /usr/bin/swift
