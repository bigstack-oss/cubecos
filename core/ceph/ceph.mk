# Cube SDK
# ceph packages

# Reef 18.2.8 is the last release in the reef series (2026-03-20); reef and quincy
# are both archived upstream, so this is a hop, not a destination -- squid (19.2.z)
# is the next one and is reachable directly from here. Ceph only supports upgrading
# across two majors, so quincy -> reef -> squid is the supported path and
# quincy -> tentacle is not.
CEPH_VERSION:=-18.2.8-1.el9s
# nfs-ganesha stays on 5.9: its ceph FSAL links libcephfs.so.2, the same soname reef
# provides, so the ganesha packages are unaffected by the major bump. Verified
# against nfs-ganesha-ceph-5.9-2.el9s and -6.5-1.el9s -- both carry the same soname
# dependency, so moving to 6.x buys nothing here and is left for the squid hop.
GANESHA_VERSION:=-5.9-1.el9s
ROOTFS_DNF_NOARCH_P1 += python3-rados$(CEPH_VERSION) python3-rbd$(CEPH_VERSION)
ROOTFS_DNF += ceph$(CEPH_VERSION) ceph-mds$(CEPH_VERSION) ceph-radosgw$(CEPH_VERSION) rbd-mirror$(CEPH_VERSION) bc liburing
# FIXME: tcmu-runner for el9/python3.9 is not yet available
ROOTFS_DNF += nfs-ganesha-ceph$(GANESHA_VERSION) nfs-ganesha-rados-grace$(GANESHA_VERSION)
ROOTFS_DNF_NOARCH += s3cmd ceph-mgr-dashboard$(CEPH_VERSION) python3-rtslib targetcli ceph-volume$(CEPH_VERSION)
# FIXME: ceph-iscsi for el9/python3.9 is not yet available (Latest is ceph-iscsi 3.6-2 el8 which depends on python3.6)
# ROOTFS_DNF_DL_FROM += https://download.ceph.com/ceph-iscsi/latest/rpm/el8/noarch/ceph-iscsi-3.6-2.el8.noarch.rpm

# These three stay on the *system* python 3.9 and cannot move into the ceph venv
# below, however much we would like them isolated.
#
# ceph-mgr is a C++ binary with an embedded interpreter: the reef rpm carries a hard
# `libpython3.9.so.1.0()(64bit)` dependency, so every mgr module -- dashboard,
# prometheus, restful -- is imported by that 3.9 interpreter and can only ever see
# /usr/lib64/python3.9/site-packages. python3-saml and xmlsec back the dashboard's
# SAML2 SSO controller (dashboard/controllers/saml2.py does
# `from onelogin.saml2.auth import ...`), which is the IdP path config_ceph.cpp's
# ceph_dashboard_idp module configures, so pointing them anywhere else silently
# turns dashboard SSO into "Required library not found: python3-saml".
#
# mon, osd, mds and radosgw are unaffected either way -- their reef rpms declare no
# python dependency at all, they are pure C++.
ROOTFS_PIP += python-magic python3-saml xmlsec

# ceph mgr module enable dashboard/prometheus failed with unknown version when
# python3-jaraco-text is 4.0.0-2.el9. Kept across the reef bump: reef's mgr still
# resolves module versions through pkg_resources on the same system python 3.9, so
# nothing about the bump retires this. Re-verify with
# `ceph mgr module ls` + `ceph mgr module enable dashboard` before dropping it.
ROOTFS_DNF_NOARCH += python3-jaraco-text-3.2.0-6.el9s
LOCKED_DNF += python3-jaraco-text-3.2.0-6.el9s

# headers for the rados/rbd python bindings built below
ROOTFS_DNF += librados-devel$(CEPH_VERSION) librbd-devel$(CEPH_VERSION)

CEPH_REPO = $(shell cp $(COREDIR)/ceph/ceph.repo $(ROOTDIR)/etc/yum.repos.d/ ; echo "ceph")

# ceph's python 3.11 BUILD context -- removed again before the image ships
#
# Ceph is the only component that needed build tooling inside somebody else's venv:
# the rados/rbd bindings are Cython C extensions, so building them used to mean
# `pip install "Cython<3"` into the antelope venv *and* the caracal venv, leaving a
# build-time compiler installed in two openstack runtime environments for the life of
# the image. That tooling lives here instead, so neither openstack venv is touched by
# ceph any more.
#
# This venv is scaffolding, not a runtime environment. Nothing on a running node
# imports from it: the wheels it produces are installed into the caracal venv, which
# is where cinder, glance and manila -- the services that talk to the built-in RBD
# store -- actually live, and once that is done there is no consumer left. It is
# deleted at the end of the binding step so the shipped image carries neither it nor
# Cython.
#
# It cannot host ceph itself, either, which is worth stating so it is not tried
# again: mon, osd, mds and radosgw declare no python dependency at all (pure C++),
# and ceph-mgr embeds its interpreter via a hard libpython3.9.so.1.0 link, so its
# modules can only ever load from /usr/lib64/python3.9/site-packages. Moving the mgr
# to 3.11 is a `-DWITH_PYTHON3=3.11` source build of ceph, not a venv.
#
# 3.11 to match the caracal venv: a C extension is only importable by the minor it
# was built for. The antelope venv no longer holds an RBD consumer, which is why the
# second (cpython-310) build that used to run here is gone.
CEPH_PYTHON_VER := 3.11
CEPH_HOME_DIR := /opt/ceph

# setuptools is pinned rather than left to float. Unpinned, the version is whatever
# the index serves on the day of the build, which is how the antelope venv acquired a
# setuptools with no pkg_resources and started failing on a date rather than on a
# commit (see the NOTE in core/heavyfs/Makefile). 75.6.0 is the same value the
# caracal venv settled on -- below 80, which removed `setup.py install`, and below
# 82, which deleted pkg_resources.
CEPH_VENV_SETUPTOOLS := 75.6.0

# Cython<3 because that is what reef itself builds against: ceph.spec.in's
# BuildRequires is the el9s python3-Cython (0.29.x). Reef's rbd/setup.py does carry a
# Cython 3 branch (it sets legacy_implicit_noexcept when it sees one), so 3.x would
# also compile, but 0.29.x is the combination upstream ships and tests.
#
# `packaging` is a reef-only requirement and is easy to miss: reef's
# src/pybind/rbd/setup.py gained a top-level `from packaging import version` that
# quincy's did not have, and with --no-build-isolation that import is resolved
# against this venv rather than a throwaway overlay. Without it the rbd build dies at
# setup.py import time, before a single line is compiled. rados/setup.py is byte
# for byte identical between 17.2.6 and 18.2.8 and needs nothing new.
CEPH_VENV_BUILD_REQS := "Cython<3" packaging wheel

CEPH_PYBIND_VERSION := 18.2.8
CEPH_PYBIND_SRCDIR := /usr/src/ceph/ceph-$(CEPH_PYBIND_VERSION)
CEPH_PYBIND_CFLAGS := -I$(CEPH_PYBIND_SRCDIR)/src/include
CEPH_WHEEL_DIR := /usr/src/ceph/wheels

# create the ceph venv and its build tooling
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(CEPH_HOME_DIR)
	$(Q)chroot $(ROOTDIR) python$(CEPH_PYTHON_VER) -m venv $(CEPH_HOME_DIR)
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) $(CEPH_HOME_DIR)/bin/pip install --upgrade pip
	$(Q)chroot $(ROOTDIR) $(CEPH_HOME_DIR)/bin/pip install --upgrade setuptools==$(CEPH_VENV_SETUPTOOLS)
	$(Q)chroot $(ROOTDIR) $(CEPH_HOME_DIR)/bin/pip install $(CEPH_VENV_BUILD_REQS)
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# build the rados/rbd bindings once, here, then install the wheels into the caracal venv
#
# `pip wheel`, not `pip install .`: the artifact has to be installable into a second
# venv, and a wheel is the only output that carries over. --no-build-isolation keeps
# the build against this venv's own Cython and setuptools instead of the throwaway
# overlay pip would otherwise create (which would resolve Cython off the index, and
# a Cython 3 at that). --no-deps because neither binding declares a dependency, so
# nothing should be resolved against the index at this point.
rootfs_install::
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) mkdir -p /usr/src/ceph $(CEPH_WHEEL_DIR)
	$(Q)chroot $(ROOTDIR) wget -O /usr/src/ceph/ceph-v$(CEPH_PYBIND_VERSION).tar.gz https://github.com/ceph/ceph/archive/refs/tags/v$(CEPH_PYBIND_VERSION).tar.gz
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) tar -xzf /usr/src/ceph/ceph-v$(CEPH_PYBIND_VERSION).tar.gz -C /usr/src/ceph
	$(Q)for b in rados rbd ; do \
		chroot $(ROOTDIR) bash -c "cd $(CEPH_PYBIND_SRCDIR)/src/pybind/$$b && CFLAGS='$(CEPH_PYBIND_CFLAGS)' $(CEPH_HOME_DIR)/bin/pip wheel --no-build-isolation --no-deps -w $(CEPH_WHEEL_DIR) ." ; \
	done
	$(Q)chroot $(ROOTDIR) bash -c "$(CARACAL_OPENSTACK_HOME_DIR)/bin/pip install --no-deps $(CEPH_WHEEL_DIR)/rados-*.whl $(CEPH_WHEEL_DIR)/rbd-*.whl"
	$(Q)# fail the build here rather than at first RBD I/O if either binding did not land
	$(Q)chroot $(ROOTDIR) $(CARACAL_OPENSTACK_HOME_DIR)/bin/python -c "import rados, rbd"
	$(Q)# tear the scaffolding down: the venv, its Cython, the wheels and the source
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
