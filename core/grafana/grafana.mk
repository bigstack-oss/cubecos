# Cube SDK
# grafana installation

# Grafana 10.1.5, 10.0.9, 9.5.13, and 9.4.17. These patch releases contain a fix for CVE-2023-4822, a medium severity security vulnerability in the role-based access control (RBAC) system
# ROOTFS_DNF += grafana
ROOTFS_DNF_DL_FROM += https://dl.grafana.com/enterprise/release/grafana-enterprise-10.1.5-1.x86_64.rpm

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
