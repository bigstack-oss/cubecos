# Cube SDK
# mysql installation

# Unknown system variable 'innodb_version' since MariaDB 10.10
# ROOTFS_DNF += mariadb-server mariadb-server-galera rsync
# rpmfind.net is often not responsive
# MARIADB_URL := https://rpmfind.net/linux/centos-stream/9-stream/AppStream/x86_64/os/Packages

MARIADB_VER := 10.6.27-1.el9
GALERA_VER := 26.4.27-1.el9
MARIADB_URL := https://archive.mariadb.org/yum/10.6/rocky9-amd64/rpms

# Official MariaDB package list
# Note: we dropped errmsg and server-utils as they are now bundled
MARIADB_LOCKED_RPMS := MariaDB-client-$(MARIADB_VER) \
                       MariaDB-server-$(MARIADB_VER) \
                       MariaDB-common-$(MARIADB_VER) \
                       MariaDB-shared-$(MARIADB_VER) \
                       MariaDB-backup-$(MARIADB_VER) \
                       MariaDB-gssapi-server-$(MARIADB_VER)

# Galera library is versioned differently than the database engine
GALERA_RPM := galera-4-$(GALERA_VER)

LOCKED_DNF += $(MARIADB_LOCKED_RPMS) $(GALERA_RPM)
BLKLST_DNF += mariadb-connector-c mariadb-connector-c-config

# Map URLs for MariaDB packages
$(foreach mariadb_rpm,$(MARIADB_LOCKED_RPMS),$(eval ROOTFS_DNF_DL_FROM += $(MARIADB_URL)/$(mariadb_rpm).x86_64.rpm))

# Map URL for Galera package
ROOTFS_DNF_DL_FROM += $(MARIADB_URL)/$(GALERA_RPM).x86_64.rpm

ROOTFS_DNF += rsync
ROOTFS_DNF_NOARCH += python3-PyMySQL

# config_mysql.cpp points log_error at /var/log/mariadb/mysql_error.log, but nothing
# created that directory: the MariaDB.org rpms ship no /var/log/mariadb (the distro
# mariadb package does, and we do not install it). mariadbd could not open its error log
# and fell back to stderr, so the database had no error log on disk at all.
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 750 /var/log/mariadb
	$(Q)chroot $(ROOTDIR) chown mysql:mysql /var/log/mariadb

rootfs_install::
	$(Q)# /etc/my.cnf.d/galera.cnf came from centos stream 9 appstream repo, mariadb repo mariadb does not have this default config
	$(Q)# mv $(ROOTDIR)/etc/my.cnf.d/galera.cnf $(ROOTDIR)/etc/my.cnf.d/galera.cnf.orig
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/default_dbs/
	$(Q)chroot $(ROOTDIR) sh -c "tar -cf - var/lib/mysql | pigz -9 > /etc/default_dbs/mysql.tgz"
