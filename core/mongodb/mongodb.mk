# Cube SDK
# mongodb installation

MONGODB_BINARY := /usr/bin/mongod
MONGODB_LOG_DIR := /var/log/mongodb

# The shell moves with the server: 2.2.15 was built months before 8.0 existed,
# and mongosh is only supported against server releases it shipped alongside.
# Both are pinned by version so the pair that was tested together stays together.
MONGODB_VER := 8.0.29
MONGOSH_VER := 2.9.2

MONGODB_PKG := mongodb-org-server-$(MONGODB_VER)-1.el9.x86_64.rpm
MONGOSH_PKG := mongodb-mongosh-shared-openssl3-$(MONGOSH_VER).x86_64.rpm

ROOTFS_DNF_DL_FROM += https://repo.mongodb.org/yum/redhat/9/mongodb-org/8.0/x86_64/RPMS/$(MONGODB_PKG)
ROOTFS_DNF_DL_FROM += https://downloads.mongodb.com/compass/$(MONGOSH_PKG)
# The server is checked against MongoDB's 8.0 release key. mongosh is signed with a key of its own
# that expires on 2026-12-20, so it is pinned by its sha256 instead, taken from the copy that
# verified against that key: bump the sum with the version.
GPGKEY_DNF += $(COREDIR)/mongodb/RPM-GPG-KEY-mongodb-server-8.0 4B0752C1BCA238C0B4EE14DC41DE058A4E7DCA05
PINNED_DNF += 7774dfcaa1e4e7820bd28bddf461d356600644ab33e7e631295a053747e155ca $(MONGOSH_PKG)

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(MONGODB_LOG_DIR)
	$(Q)chroot $(ROOTDIR) chown mongod:mongod $(MONGODB_BINARY) $(MONGODB_LOG_DIR)
	$(Q)chroot $(ROOTDIR) rm -rf ./lib/systemd/system/mongod.service
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/mongodb/mongodb.service ./lib/systemd/system
	$(Q)chroot $(ROOTDIR) mv /etc/mongod.conf /etc/mongod.conf.org
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/mongodb/mongod.conf.in ./etc/mongod.conf.in
