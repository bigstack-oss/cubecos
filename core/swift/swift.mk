# Cube SDK
# swift installation

# install the swift client inside the caracal virtual environment.
# note: the pypi package is python-swiftclient; the "swift" package is the
# swift *server*, which CubeCOS does not ship (ceph rgw serves object-store --
# config_swift.cpp:145-147 points all three endpoints at rgw's 8888).
#
# #642 moves the client from the antelope venv to the caracal one, and it is the
# smallest stop on the hop because there is no server to move: the client and the
# /usr/bin/swift symlink below are the whole of it.
#
# The install is a re-declaration rather than a first install. horizon 24.0.2's down
# payment into this venv (core/horizon/horizon.mk, the second rootfs_install::) runs
# without --no-deps, and horizon 24.0.2 declares python-swiftclient >=3.2.0, so the
# ===4.5.0 pinned in os-caracal-pip-upper-constraints.txt:103 is already installed by
# the time this file runs. Naming it here keeps the object-store client an explicit
# part of the object-store story rather than an accident of horizon's dependency set
# -- the same reason it was named while it lived in the antelope venv.
#
# Two library consumers keep it from being a convenience CLI only, and both live in
# the caracal venv as of #629: the `cube-swift` cinder backup type
# (config_cinder.cpp:651-652) and, more importantly, cinder's *default* backup driver
# (config_cinder.cpp:671-672), which is SwiftBackupDriver as well. Leaving the client
# behind in antelope would have pointed this file's install and cinder's import at
# two different copies.
#
# History, in case the paths below read as over-specified: the pip-installed yoga copy
# under /usr/local/lib/python3.9/site-packages went away in #609. It had been dragged
# in by the dashboard plugins, which all required horizon 22.1.1 and therefore
# python-swiftclient under the yoga constraint, and none of them installs into python
# 3.9 any more.
#
# The python3-swiftclient rpm survives in the system python, but nothing asks for it
# any longer: it was pulled in as a dependency of python3-heatclient (retired with the
# osc move), python3-troveclient and openstack-ironic-common. It is not named here
# either way -- this file installs the venv client, and the rpm's /usr/bin/swift is
# overwritten by the symlink below.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(CARACAL_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-swiftclient==4.5.0"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries. This overwrites a path owned by the python3-swiftclient
	$(Q)# rpm, and it now wins PATH as well: the pip-installed yoga copy that owned
	$(Q)# /usr/local/bin/swift -- which precedes /usr/bin -- came in with horizon,
	$(Q)# and #609 moved horizon into the venv, so a bare "swift" is caracal 4.5.0.
	$(Q)chroot $(ROOTDIR) ln -sf $(CARACAL_OPENSTACK_HOME_DIR)/bin/swift /usr/bin/swift
