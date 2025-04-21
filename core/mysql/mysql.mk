# Cube SDK
# mysql installation

# Unknown system variable 'innodb_version' since MariaDB 10.10
# ROOTFS_DNF += mariadb-server mariadb-server-galera rsync
MARIADB_VER := 10.5.27-1.el9
MARIADB_URL := https://rpmfind.net/linux/centos-stream/9-stream/AppStream/x86_64/os/Packages
MARIADB_LOCKED_RPMS := mariadb-$(MARIADB_VER) mariadb-backup-$(MARIADB_VER) mariadb-common-$(MARIADB_VER) mariadb-errmsg-$(MARIADB_VER)
MARIADB_LOCKED_RPMS += mariadb-gssapi-server-$(MARIADB_VER) mariadb-server-$(MARIADB_VER) mariadb-server-galera-$(MARIADB_VER) mariadb-server-utils-$(MARIADB_VER)
LOCKED_DNF += $(MARIADB_LOCKED_RPMS)
$(foreach mariadb_rpm,$(MARIADB_LOCKED_RPMS),$(eval ROOTFS_DNF_DL_FROM += $(MARIADB_URL)/$(mariadb_rpm).x86_64.rpm))
ROOTFS_DNF += rsync
ROOTFS_DNF_NOARCH += python3-PyMySQL

rootfs_install::
	$(Q)mv $(ROOTDIR)/etc/my.cnf.d/galera.cnf $(ROOTDIR)/etc/my.cnf.d/galera.cnf.orig
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/default_dbs/
	$(Q)chroot $(ROOTDIR) sh -c "tar -cf - var/lib/mysql | pigz -9 > /etc/default_dbs/mysql.tgz"
