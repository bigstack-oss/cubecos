# Cube SDK
# mongodb installation

MONGODB_BINARY := /usr/bin/mongod
MONGODB_LOG_DIR := /var/log/mongodb

MONGODB_PKG := mongodb-org-server-7.0.12-1.el9.x86_64.rpm
MONGOSH_PKG := mongodb-mongosh-shared-openssl3-2.2.15.x86_64.rpm

ROOTFS_DNF_DL_FROM += https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/RPMS/$(MONGODB_PKG)
ROOTFS_DNF_DL_FROM += https://downloads.mongodb.com/compass/$(MONGOSH_PKG)

rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf ./lib/systemd/system/mongod.service
	$(Q)chroot $(ROOTDIR) mkdir -p $(MONGODB_LOG_DIR)
	$(Q)chroot $(ROOTDIR) chown mongod:mongod $(MONGODB_BINARY) $(MONGODB_LOG_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/mongodb/mongodb.service ./lib/systemd/system
