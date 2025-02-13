# Cube SDK
# Influxdb installation

# Install InfluxDBClieSnt python module for ceph influx plugin
ROOTFS_PIP += influxdb toml

ROOTFS_DNF += influxdb

INFLUXDB_REPO = $(shell cp $(COREDIR)/influxdb/influxdb.repo $(ROOTDIR)/etc/yum.repos.d/ ; echo "influxdb")

rootfs_install::
	$(Q)chroot $(ROOTDIR) systemctl disable influxdb
	$(Q)mv -f $(ROOTDIR)/etc/influxdb/influxdb.conf $(ROOTDIR)/etc/influxdb/influxdb.conf.org
	$(Q)cp -f $(COREDIR)/influxdb/influxdb.conf $(ROOTDIR)/etc/influxdb/
	$(Q)chroot $(ROOTDIR) chown -R influxdb:influxdb /usr/share/influxdb
