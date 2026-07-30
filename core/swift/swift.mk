# Cube SDK
# swift installation

# install the swift client inside the python 3.10 virtual environment.
# note: the pypi package is python-swiftclient; the "swift" package is the
# swift *server*, which CubeCOS does not ship (ceph rgw serves object-store).
#
# This does not remove yoga's swiftclient (3.13.1) from the image, and cannot
# yet. Two copies survive in the system python 3.9:
#
#   1. the python3-swiftclient rpm, which dnf keeps pulling in as a dependency
#      of python3-heatclient, python3-troveclient, openstack-ironic-common,
#      openstack-dashboard and openstack-heat-common. Dropping it from
#      ROOTFS_DNF_NOARCH here does not uninstall it.
#   2. a pip-installed copy under /usr/local/lib/python3.9/site-packages,
#      dragged in by horizon: designate-dashboard, masakari-dashboard and
#      watcher-dashboard all require horizon 22.1.1, and horizon requires
#      python-swiftclient, so it is resolved under the yoga constraint. Those
#      plugins install after swift in HEAVY_COMPONENTS, so they win any race.
#
# Remove both once horizon itself moves into the venv. The venv install below
# still matters meanwhile: cinder's SwiftBackupDriver imports swiftclient from
# the venv, and installing it here makes that explicit rather than relying on
# cinder to pull it in transitively.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		python-swiftclient==4.2.0"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries. This overwrites a path owned by the python3-swiftclient
	$(Q)# rpm, and it does not win PATH: horizon's pip-installed copy owns
	$(Q)# /usr/local/bin/swift, which precedes /usr/bin, so a bare "swift" is
	$(Q)# still yoga 3.13.1. Antelope's client is reachable explicitly as
	$(Q)# /opt/openstack-antelope/bin/swift until horizon leaves python 3.9.
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/swift /usr/bin/swift
