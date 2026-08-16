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
# MariaDB-devel carries mysql.h and mariadb_config. core/horizon/horizon.mk builds
# the mysqlclient wheel from source -- upstream publishes wheels for windows only --
# and django.db.backends.mysql needs it for horizon's session store. It has to come
# from this MariaDB.org build rather than appstream's mariadb-connector-c-devel,
# because MariaDB-shared obsoletes mariadb-connector-c, which that package requires.
MARIADB_LOCKED_RPMS := MariaDB-client-$(MARIADB_VER) \
                       MariaDB-server-$(MARIADB_VER) \
                       MariaDB-common-$(MARIADB_VER) \
                       MariaDB-shared-$(MARIADB_VER) \
                       MariaDB-backup-$(MARIADB_VER) \
                       MariaDB-gssapi-server-$(MARIADB_VER) \
                       MariaDB-devel-$(MARIADB_VER)

# Galera library is versioned differently than the database engine
GALERA_RPM := galera-4-$(GALERA_VER)

LOCKED_DNF += $(MARIADB_LOCKED_RPMS) $(GALERA_RPM)
BLKLST_DNF += mariadb-connector-c mariadb-connector-c-config

# Map URLs for MariaDB packages
$(foreach mariadb_rpm,$(MARIADB_LOCKED_RPMS),$(eval ROOTFS_DNF_DL_FROM += $(MARIADB_URL)/$(mariadb_rpm).x86_64.rpm))

# Map URL for Galera package
ROOTFS_DNF_DL_FROM += $(MARIADB_URL)/$(GALERA_RPM).x86_64.rpm

# zlib-devel pairs with MariaDB-devel above: mysqlclient links against libz.
#
# Neither needs stripping in a trailing rootfs_install::. core/main/cube-post.mk
# already autoremoves every installed package matching "devel|headers" (all but
# python3-devel) from the rootfs as its final cleanup, so both go there, and the
# toolchain goes with them -- erasing glibc-devel takes gcc, gcc-c++ and
# libstdc++-devel out as dependents. Only the runtime halves are left for
# mysqlclient to link against at import time: MariaDB-shared for libmariadb.so.3
# and zlib for libz.so.1.
ROOTFS_DNF += rsync zlib-devel
ROOTFS_DNF_NOARCH += python3-PyMySQL

# config_mysql.cpp points log_error at /var/log/mariadb/mysql_error.log, but nothing
# created that directory: the MariaDB.org rpms ship no /var/log/mariadb (the distro
# mariadb package does, and we do not install it). mariadbd could not open its error log
# and fell back to stderr, so the database had no error log on disk at all.
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 750 /var/log/mariadb
	$(Q)chroot $(ROOTDIR) chown mysql:mysql /var/log/mariadb

# see the drop-in for why upstream's stop semantics are not safe across a reboot
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/mariadb.service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/mysql/mariadb-stop.conf ./etc/systemd/system/mariadb.service.d/

rootfs_install::
	$(Q)# /etc/my.cnf.d/galera.cnf came from centos stream 9 appstream repo, mariadb repo mariadb does not have this default config
	$(Q)# mv $(ROOTDIR)/etc/my.cnf.d/galera.cnf $(ROOTDIR)/etc/my.cnf.d/galera.cnf.orig
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/default_dbs/
	$(Q)chroot $(ROOTDIR) sh -c "tar -cf - var/lib/mysql | pigz -9 > /etc/default_dbs/mysql.tgz"
