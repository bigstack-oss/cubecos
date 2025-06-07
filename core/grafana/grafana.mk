# Cube SDK
# grafana installation

# ROOTFS_DNF += grafana
ROOTFS_DNF_DL_FROM += https://dl.grafana.com/enterprise/release/grafana-enterprise-10.1.10-1.x86_64.rpm

rootfs_install::
	$(Q)mount -t proc proc $(ROOTDIR)/proc
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/resolv.conf
	$(Q)chroot $(ROOTDIR) grafana-cli plugins install vonage-status-panel
	$(Q)chroot $(ROOTDIR) grafana-cli plugins install grafana-piechart-panel
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)umount $(ROOTDIR)/proc
	# Configuration and dashboards provisioning
	$(Q)cp -rf $(COREDIR)/grafana/provisioning $(ROOTDIR)/etc/grafana/
	#$(Q)mv -f $(ROOTDIR)/etc/grafana/grafana.ini $(ROOTDIR)/etc/grafana/grafana.ini.org

# data syncing
rootfs_install::
	$(Q)cp -rf $(ROOTDIR)/etc/grafana/dashboards/ceph-dashboard/* $(ROOTDIR)/etc/grafana/provisioning/dashboards/
	$(Q)chmod 0644 $(ROOTDIR)/etc/grafana/provisioning/dashboards/*
