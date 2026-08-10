# Cube SDK
# swift installation

# install the swift client inside the python 3.10 virtual environment.
# note: the pypi package is python-swiftclient; the "swift" package is the
# swift *server*, which CubeCOS does not ship (ceph rgw serves object-store).
#
# The pip-installed yoga copy under /usr/local/lib/python3.9/site-packages is gone as
# of #609: it was dragged in by the dashboard plugins, which all required horizon
# 22.1.1 and therefore python-swiftclient under the yoga constraint, and none of them
# installs into python 3.9 any more.
#
# The python3-swiftclient rpm survives in the system python, but nothing asks for it
# any longer: it was pulled in as a dependency of python3-heatclient (retired with the
# osc move), python3-troveclient and openstack-ironic-common. It is not named here
# either way -- this file installs the venv client, and the rpm's /usr/bin/swift is
# overwritten by the symlink below.
#
# The venv install below is what cinder's SwiftBackupDriver imports; naming it here
# makes that explicit rather than relying on cinder to pull it in transitively.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-swiftclient==4.2.0"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries. This overwrites a path owned by the python3-swiftclient
	$(Q)# rpm, and it now wins PATH as well: the pip-installed yoga copy that owned
	$(Q)# /usr/local/bin/swift -- which precedes /usr/bin -- came in with horizon,
	$(Q)# and #609 moved horizon into the venv, so a bare "swift" is antelope 4.2.0.
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/swift /usr/bin/swift
