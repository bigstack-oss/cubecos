# Cube SDK
# ceph packages

# ceph-17.2.6-4.el9s + python3-cherrypy-18.6.1-2 + CherryPy===18.6.1 to avoid dashboard->Object Gateway 500 error
# ENGINE HTTP Server cherrypy._cpwsgi_server.CPWSGIServer(('0.0.0.0', 9283)) shut down
CEPH_VERSION:=-17.2.6-4.el9s
GANESHA_VERSION:=-5.9-1.el9s
ROOTFS_DNF_NOARCH_P1 += python3-rados$(CEPH_VERSION) python3-rbd$(CEPH_VERSION)
ROOTFS_DNF += ceph$(CEPH_VERSION) ceph-mds$(CEPH_VERSION) ceph-radosgw$(CEPH_VERSION) rbd-mirror$(CEPH_VERSION) bc liburing
# FIXME: tcmu-runner for el9/python3.9 is not yet available
ROOTFS_DNF += nfs-ganesha-ceph$(GANESHA_VERSION) nfs-ganesha-rados-grace$(GANESHA_VERSION)
ROOTFS_DNF_NOARCH += s3cmd ceph-mgr-dashboard$(CEPH_VERSION) python3-rtslib targetcli ceph-volume$(CEPH_VERSION)
# FIXME: ceph-iscsi for el9/python3.9 is not yet available (Latest is ceph-iscsi 3.6-2 el8 which depends on python3.6)
# ROOTFS_DNF_DL_FROM += https://download.ceph.com/ceph-iscsi/latest/rpm/el8/noarch/ceph-iscsi-3.6-2.el8.noarch.rpm

# FIXME:  scikit-learn needed by ceph mgr module diskprediction
ROOTFS_PIP += python-magic python3-saml xmlsec

# ceph mgr module enable dashboard/prometheus failed with unknown version when python3-jaraco-text is 4.0.0-2.el9
ROOTFS_DNF_NOARCH += python3-jaraco-text-3.2.0-6.el9s
LOCKED_DNF += python3-jaraco-text-3.2.0-6.el9s

# build ceph python bindings for python 3.10 used by openstack antelope
ROOTFS_DNF += librados-devel$(CEPH_VERSION) librbd-devel$(CEPH_VERSION)

# Not $(OPENSTACK_RELEASE)_patch: this patches the ceph dashboard (a token.decode()
# on an already-str token), under /usr/share/ceph/mgr where ceph-mgr runs on the
# system python. It was only ever *named* by the openstack release and has nothing to
# do with one -- deriving it from the release meant that promoting OPENSTACK_RELEASE
# to antelope silently pointed it at a directory that does not exist, and the
# "[ -d ] && cp || /bin/true" guard below would have swallowed that.
CEPH_PATCHDIR := $(COREDIR)/ceph/patch

CEPH_REPO = $(shell cp $(COREDIR)/ceph/ceph.repo $(ROOTDIR)/etc/yum.repos.d/ ; echo "ceph")

# build ceph python bindings for python 3.10 used by openstack antelope
rootfs_install::
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install "Cython<3"
	$(Q)chroot $(ROOTDIR) mkdir -p /usr/src/ceph
	$(Q)chroot $(ROOTDIR) wget -O /usr/src/ceph/ceph-v17.2.6.tar.gz https://github.com/ceph/ceph/archive/refs/tags/v17.2.6.tar.gz
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) tar -xvzf /usr/src/ceph/ceph-v17.2.6.tar.gz -C /usr/src/ceph
	$(Q)chroot $(ROOTDIR) bash -c "cd /usr/src/ceph/ceph-17.2.6/src/pybind/rados && CFLAGS='-I/usr/src/ceph/ceph-17.2.6/src/include' /opt/openstack-antelope/bin/python setup.py install"
	$(Q)chroot $(ROOTDIR) bash -c "cd /usr/src/ceph/ceph-17.2.6/src/pybind/rbd && CFLAGS='-I/usr/src/ceph/ceph-17.2.6/src/include' /opt/openstack-antelope/bin/python setup.py install"

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

rootfs_install::
	$(Q)[ -d $(CEPH_PATCHDIR) ] && (cd $(CEPH_PATCHDIR) && rsync -ar . $(ROOTDIR)/) || /bin/true

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
