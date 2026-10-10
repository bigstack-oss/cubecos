# Cube SDK
# Influxdb installation

# The influxdb python client was installed here for ceph's influx mgr module, which
# config_ceph.cpp now retires (RetireMgrInflux), and nothing else imports it. It goes from pip
# and, as the rpm ceph-mgr only recommends, through the blocklist -- with msgpack in both
# places, which only the client requires and which carries known vulnerabilities in both.
# toml, installed alongside it, stays.
ROOTFS_PIP += toml
BLKLST_DNF += python3-influxdb python3-msgpack

ROOTFS_DNF += influxdb

INFLUXDB_REPO = $(shell cp $(COREDIR)/influxdb/influxdb.repo $(ROOTDIR)/etc/yum.repos.d/ ; echo "influxdb")

rootfs_install::
	$(Q)chroot $(ROOTDIR) systemctl disable influxdb
	$(Q)mv -f $(ROOTDIR)/etc/influxdb/influxdb.conf $(ROOTDIR)/etc/influxdb/influxdb.conf.org
	$(Q)cp -f $(COREDIR)/influxdb/influxdb.conf $(ROOTDIR)/etc/influxdb/
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/influxdb.service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/influxdb/influxdb-start-timeout.conf ./etc/systemd/system/influxdb.service.d/
