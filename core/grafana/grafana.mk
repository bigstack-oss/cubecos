# Cube SDK
# grafana installation

# ROOTFS_DNF += grafana
# 12.4 is the last minor of major 12, which is Grafana's LTS equivalent: an ordinary minor is
# supported for 9 months, the final minor of a major for 15. 12.4 is therefore supported to
# 2027-05-24 -- the longest window of any current release, a few days past even the newest
# (13.2, to 2027-05-18). 12.3 went end-of-life on 2026-08-19, so 12.3.2 is both EOL and nine
# patches behind its own dead line.
ROOTFS_DNF_DL_FROM += https://dl.grafana.com/enterprise/release/grafana-enterprise-12.4.10-1.x86_64.rpm

# No grafana-cli plugin installs. Both plugins this used to fetch are gone:
# grafana-piechart-panel is AngularJS, which Grafana 12 removed, so it could not load at all
# and its panels were migrated to the core piechart in 629c561a; vonage-status-panel loads
# fine but has been used by zero dashboards since the initial commit -- 376K of nothing.
# The resolv.conf copy went with them: it existed only so grafana-cli could reach
# grafana.com from inside the chroot.
rootfs_install::
	# Configuration and dashboards provisioning
	$(Q)cp -rf $(COREDIR)/grafana/provisioning $(ROOTDIR)/etc/grafana/
	#$(Q)mv -f $(ROOTDIR)/etc/grafana/grafana.ini $(ROOTDIR)/etc/grafana/grafana.ini.org

# data syncing
rootfs_install::
	$(Q)cp -rf $(ROOTDIR)/etc/grafana/dashboards/ceph-dashboard/* $(ROOTDIR)/etc/grafana/provisioning/dashboards/
	$(Q)chmod 0644 $(ROOTDIR)/etc/grafana/provisioning/dashboards/*
