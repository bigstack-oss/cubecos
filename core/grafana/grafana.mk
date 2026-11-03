# Cube SDK
# grafana installation

# ROOTFS_DNF += grafana
# 13.3, the newest minor, is the first release whose grafana-server links go-jose and
# klauspost/compress past their fixes (4.1.6 and 1.20.3); 12.4.14 and 13.2.5, the newest patches of
# the 12.4 and 13.2 lines, still link go-jose 4.1.4. An ordinary minor is supported for 9 months
# and the final minor of a major for 15, so 13.3, released 2026-10-27, is supported to about
# 2027-07-27, past 12.4's 2027-05-24.
ROOTFS_DNF_DL_FROM += https://dl.grafana.com/enterprise/release/grafana-enterprise-13.3.0-1.x86_64.rpm
# Grafana Labs' rpm signing key, which expires 2027-08-22; a release signed with its successor
# fails installdnf's check, naming the new key ID
GPGKEY_DNF += $(COREDIR)/grafana/RPM-GPG-KEY-grafana B53AE77BADB630A683046005963FA27710458545

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
