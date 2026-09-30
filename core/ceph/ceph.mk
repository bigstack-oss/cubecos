# Cube SDK
# ceph packages

# Squid, from reef 18.2.8 -- the last reef release, and archived upstream like quincy
# before it. Ceph only supports upgrading across two majors: squid's notes cover
# "Upgrading from Quincy or Reef", and tentacle's require reef or squid first, so
# quincy -> reef -> squid -> tentacle is the path and every hop keeps the next door
# open.
#
# 19.2.5 is the newest squid the Storage SIG has released. 19.2.6 (2026-08-19) is
# the CVE release -- CephX auth bypass CVE-2025-30156, mon config-key read
# CVE-2026-50152, RGW SigV4 CVE-2026-54330 and RGW STS CVE-2026-39944 -- and is only
# in the SIG's testing repo. It is not a drop-in bump either: its CephX fix adds the
# aes256k key type, an upgraded cluster reports HEALTH_ERR
# (AUTH_INSECURE_SERVICE_TICKETS, AUTH_INSECURE_SERVICE_KEY_TYPE) until every key
# is rotated onto it, and the 6.12 kernel's libceph cannot use aes256k, so the
# kernel clients -- the /mnt/cephfs mount and ceph-csi's krbd/cephfs mounts --
# could never follow. Tracked on #677.
CEPH_VERSION:=-19.2.5-1.el9s
# nfs-ganesha stays on 5.9: its ceph FSAL links libcephfs.so.2 and librados.so.2,
# and squid's libcephfs2/librados2 still provide exactly those sonames, so the
# ganesha packages are untouched by the major bump -- a dnf solve of the squid set
# on a reef node upgrades 28 ceph packages and leaves both ganesha rpms alone.
GANESHA_VERSION:=-5.9-1.el9s
ROOTFS_DNF_NOARCH_P1 += python3-rados$(CEPH_VERSION) python3-rbd$(CEPH_VERSION)
# The daemons are named rather than taken through the `ceph` metapackage. From squid
# on it also requires luarocks (for RGW Lua packages, unused here) and rocksdb, and
# luarocks requires gcc. core/main/cube-post.mk autoremoves every *-devel package at
# the end of the build, and erasing glibc-devel takes gcc with it -- and, with gcc,
# luarocks and the metapackage. The metapackage owns no files, so nothing is lost by
# not installing it; installing it would only add the toolchain to the image for
# the cleanup to tear out again. Nothing in this tree queries the `ceph` package.
ROOTFS_DNF += ceph-mon$(CEPH_VERSION) ceph-mgr$(CEPH_VERSION) ceph-osd$(CEPH_VERSION)
ROOTFS_DNF += ceph-mds$(CEPH_VERSION) ceph-radosgw$(CEPH_VERSION) rbd-mirror$(CEPH_VERSION) bc liburing
# FIXME: tcmu-runner for el9/python3.9 is not yet available
ROOTFS_DNF += nfs-ganesha-ceph$(GANESHA_VERSION) nfs-ganesha-rados-grace$(GANESHA_VERSION)
ROOTFS_DNF_NOARCH += s3cmd ceph-mgr-dashboard$(CEPH_VERSION) python3-rtslib targetcli ceph-volume$(CEPH_VERSION)
# FIXME: ceph-iscsi for el9/python3.9 is not yet available (Latest is ceph-iscsi 3.6-2 el8 which depends on python3.6)
# ROOTFS_DNF_DL_FROM += https://download.ceph.com/ceph-iscsi/latest/rpm/el8/noarch/ceph-iscsi-3.6-2.el8.noarch.rpm

# These three stay on the *system* python 3.9 and cannot move into the ceph venv
# below, however much we would like them isolated.
#
# ceph-mgr is a C++ binary with an embedded interpreter: the squid rpm carries a hard
# `libpython3.9.so.1.0()(64bit)` dependency, so every mgr module -- dashboard,
# prometheus, restful -- is imported by that 3.9 interpreter and can only ever see
# /usr/lib64/python3.9/site-packages. python3-saml and xmlsec back the dashboard's
# SAML2 SSO controller (dashboard/controllers/saml2.py does
# `from onelogin.saml2.auth import ...`), which is the IdP path config_ceph.cpp's
# ceph_dashboard_idp module configures, so pointing them anywhere else silently
# turns dashboard SSO into "Required library not found: python3-saml".
#
# mon, osd, mds and radosgw are unaffected either way -- their squid rpms declare no
# python dependency at all, they are pure C++.
ROOTFS_PIP += python-magic python3-saml xmlsec

# ceph mgr module enable dashboard/prometheus failed with unknown version when
# python3-jaraco-text is 4.0.0-2.el9. Kept across the reef and squid bumps: the mgr
# still resolves module versions through pkg_resources on the same system python
# 3.9, and the squid SIG repo ships no jaraco-text of its own, so nothing about
# either bump retires this. Re-verify with
# `ceph mgr module ls` + `ceph mgr module enable dashboard` before dropping it.
ROOTFS_DNF_NOARCH += python3-jaraco-text-3.2.0-6.el9s
LOCKED_DNF += python3-jaraco-text-3.2.0-6.el9s

# headers for the rados/rbd python bindings built below
ROOTFS_DNF += librados-devel$(CEPH_VERSION) librbd-devel$(CEPH_VERSION)

CEPH_REPO = $(shell cp $(COREDIR)/ceph/ceph.repo $(ROOTDIR)/etc/yum.repos.d/ ; echo "ceph")

# ceph's python BUILD contexts, one per openstack interpreter -- removed again before
# the image ships
#
# Ceph is the only component that needed build tooling inside somebody else's venv:
# the rados/rbd bindings are Cython C extensions, so building them used to mean
# `pip install "Cython<3"` into the antelope venv *and* the caracal venv, leaving a
# build-time compiler installed in two openstack runtime environments for the life of
# the image. That tooling lives here instead, so no openstack venv is touched by
# ceph any more.
#
# These venvs are scaffolding, not runtime environments. Nothing on a running node
# imports from them: the wheels they produce are installed into the openstack venvs
# that hold a service talking to the built-in RBD store -- the epoxy one, where glance,
# cinder, nova and manila live -- and once that is done there is no consumer left. They
# are deleted at the end of the binding step so the shipped image carries neither them
# nor Cython.
#
# They cannot host ceph itself, either, which is worth stating so it is not tried
# again: mon, osd, mds and radosgw declare no python dependency at all (pure C++),
# and ceph-mgr embeds its interpreter via a hard libpython3.9.so.1.0 link, so its
# modules can only ever load from /usr/lib64/python3.9/site-packages. Moving the mgr
# to 3.11 is a `-DWITH_PYTHON3=3.11` source build of ceph, not a venv.
#
# One venv per openstack interpreter that holds an RBD consumer, because a C extension
# is only importable by the minor it was built for. glance was the first epoxy occupant
# to need the bindings -- keystone never touched ceph -- which is why this built for
# both 3.11 and 3.12 from #656 on. manila was the caracal venv's last consumer: its
# CephFS native and NFS drivers load rados through importutils, and cinder, nova and
# glance_store, the other importers there, had already left. With manila in the epoxy
# venv (#664) the caracal one holds none, so the cpython-311 build went the way the
# antelope venv's cpython-310 one did, and only 3.12 is built. The loops below keep
# their shape, so a consumer on another interpreter is one entry in each list.
CEPH_PYTHON_VERS := $(PYTHON_VER)
CEPH_OPENSTACK_VENVS := $(OPENSTACK_HOME_DIR)
CEPH_HOME_DIR := /opt/ceph

# setuptools is pinned rather than left to float. Unpinned, the version is whatever
# the index serves on the day of the build, which is how the antelope venv acquired a
# setuptools with no pkg_resources and started failing on a date rather than on a
# commit (see the NOTE in core/heavyfs/Makefile). 75.6.0 is the same value the
# caracal venv settled on -- below 80, which removed `setup.py install`, and below
# 82, which deleted pkg_resources.
CEPH_VENV_SETUPTOOLS := 75.6.0

# Cython<3 because that is what squid itself builds against: ceph.spec.in's
# BuildRequires is still the unversioned el9s python3-Cython (0.29.x), as it was
# for reef. rbd/setup.py does carry a
# Cython 3 branch (it sets legacy_implicit_noexcept when it sees one), so 3.x would
# also compile, but 0.29.x is the combination upstream ships and tests.
#
# `packaging` is a reef-only requirement and is easy to miss: reef's
# src/pybind/rbd/setup.py gained a top-level `from packaging import version` that
# quincy's did not have, and with --no-build-isolation that import is resolved
# against this venv rather than a throwaway overlay. Without it the rbd build dies at
# setup.py import time, before a single line is compiled. rados/setup.py is byte
# for byte identical between 17.2.6 and 18.2.8 and needs nothing new. Squid changed
# neither: both setup.py files are byte for byte identical between 18.2.8 and 19.2.5.
CEPH_VENV_BUILD_REQS := "Cython<3" packaging wheel

CEPH_PYBIND_VERSION := 19.2.5
CEPH_PYBIND_SRCDIR := /usr/src/ceph/ceph-$(CEPH_PYBIND_VERSION)
CEPH_PYBIND_CFLAGS := -I$(CEPH_PYBIND_SRCDIR)/src/include
CEPH_WHEEL_DIR := /usr/src/ceph/wheels

# create one ceph venv per interpreter, each with its own build tooling
#
# || exit 1 per iteration: a for loop only returns the status of its *last*
# iteration, so without it a failure for one interpreter would be hidden by a
# successful later one the day the list holds two again.
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(CEPH_HOME_DIR)
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)for v in $(CEPH_PYTHON_VERS) ; do \
		chroot $(ROOTDIR) python$$v -m venv $(CEPH_HOME_DIR)/$$v && \
		chroot $(ROOTDIR) $(CEPH_HOME_DIR)/$$v/bin/pip install --upgrade pip && \
		chroot $(ROOTDIR) $(CEPH_HOME_DIR)/$$v/bin/pip install --upgrade setuptools==$(CEPH_VENV_SETUPTOOLS) && \
		chroot $(ROOTDIR) $(CEPH_HOME_DIR)/$$v/bin/pip install $(CEPH_VENV_BUILD_REQS) || exit 1 ; \
	done
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# build the rados/rbd bindings once per interpreter, here, then install each pair into
# the openstack venv that runs that interpreter
#
# `pip wheel`, not `pip install .`: the artifact has to be installable into another
# venv, and a wheel is the only output that carries over. --no-build-isolation keeps
# the build against this venv's own Cython and setuptools instead of the throwaway
# overlay pip would otherwise create (which would resolve Cython off the index, and
# a Cython 3 at that). --no-deps because neither binding declares a dependency, so
# nothing should be resolved against the index at this point.
#
# Every interpreter's wheels land in the one directory -- rados-2.0.0-cp312-* today,
# with a cp311 pair beside it while the caracal venv still needed one -- so each venv
# installs by name from it with --no-index --find-links rather than by glob, and pip
# picks the one wheel whose tag that interpreter accepts.
rootfs_install::
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) mkdir -p /usr/src/ceph $(CEPH_WHEEL_DIR)
	$(Q)chroot $(ROOTDIR) wget -O /usr/src/ceph/ceph-v$(CEPH_PYBIND_VERSION).tar.gz https://github.com/ceph/ceph/archive/refs/tags/v$(CEPH_PYBIND_VERSION).tar.gz
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) tar -xzf /usr/src/ceph/ceph-v$(CEPH_PYBIND_VERSION).tar.gz -C /usr/src/ceph
	$(Q)for v in $(CEPH_PYTHON_VERS) ; do \
		for b in rados rbd ; do \
			chroot $(ROOTDIR) bash -c "cd $(CEPH_PYBIND_SRCDIR)/src/pybind/$$b && CFLAGS='$(CEPH_PYBIND_CFLAGS)' $(CEPH_HOME_DIR)/$$v/bin/pip wheel --no-build-isolation --no-deps -w $(CEPH_WHEEL_DIR) ." || exit 1 ; \
		done ; \
	done
	$(Q)for venv in $(CEPH_OPENSTACK_VENVS) ; do \
		chroot $(ROOTDIR) $$venv/bin/pip install --no-deps --no-index --find-links $(CEPH_WHEEL_DIR) rados rbd || exit 1 ; \
	done
	$(Q)# fail the build here rather than at first RBD I/O if either binding did not land
	$(Q)for venv in $(CEPH_OPENSTACK_VENVS) ; do \
		chroot $(ROOTDIR) $$venv/bin/python -c "import rados, rbd" || exit 1 ; \
	done
	$(Q)# tear the scaffolding down: the venvs, their Cython, the wheels and the source
	$(Q)# tree are all build-time only, and none of them belong in the shipped image
	$(Q)chroot $(ROOTDIR) rm -rf $(CEPH_HOME_DIR) /usr/src/ceph
	$(Q)# guard against a future edit leaving either behind
	$(Q)test ! -e $(ROOTDIR)$(CEPH_HOME_DIR)
	$(Q)test ! -e $(ROOTDIR)/usr/src/ceph

rootfs_install::
	$(Q)chroot $(ROOTDIR) systemctl mask lvm2-monitor
	$(Q)chroot $(ROOTDIR) systemctl disable ceph-crash libstoragemgmt
	#$(Q)mv -f $(ROOTDIR)/etc/ceph/radosgw-sync.conf $(ROOTDIR)/etc/ceph/radosgw-sync.conf.example
	$(Q)mkdir -p $(ROOTDIR)/lib/udev/disabled
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/ceph/ceph-mgr@.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/ceph/ceph-umountfs.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/ceph/ceph-osd-compact.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/ceph/61-cube-ceph-partuuid.rules ./lib/udev/rules.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/ceph/ceph-osd-compact.timer ./lib/systemd/system
	$(Q)chroot $(ROOTDIR) systemctl enable ceph-umountfs
	$(Q)chroot $(ROOTDIR) systemctl enable ceph-osd-compact.timer
	# fix systemd[1]: ceph-osd@0.service: Start request repeated too quickly
	$(Q)sed -i 's/StartLimitInterval=30min/# &/' $(ROOTDIR)/usr/lib/systemd/system/ceph-osd@.service
	#$(Q)mv $(ROOTDIR)/lib/udev/rules.d/95-ceph-osd.rules $(ROOTDIR)/lib/udev/disabled/.
	$(Q)rm -f $(ROOTDIR)/etc/ganesha/*
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/ceph/ganesha.conf ./etc/ganesha/
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/nfs-ganesha.service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/ceph/nfs-ganesha-sigkill.conf ./etc/systemd/system/nfs-ganesha.service.d/
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/cron
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/cube/cos/ceph

# install hdsentinel to assist osd disk life predictions
rootfs_install::
	$(Q)wget https://www.hdsentinel.com/hdslin/hdsentinel-020c-x64.zip
	$(Q)unzip hdsentinel*.zip
	$(Q)rm -f ./hdsentinel*.zip
	$(Q)mv HDSentinel hdsentinel
	$(Q)chmod 0755 hdsentinel
	$(Q)mv -f hdsentinel $(ROOTDIR)/usr/sbin/

# remove unused k8sevents which anyway errors when ceph-mgr starts
rootfs_install::
	$(Q)chroot $(ROOTDIR) dnf remove -y ceph-mgr-k8sevents ceph-mgr-rook ceph-mgr-cephadm ceph-mgr-diskprediction-local
