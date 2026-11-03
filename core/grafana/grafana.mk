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

# Grafana 13 ships its datasources as plugins, each with a Go binary of its own, in
# data/plugins-bundled, and the rpm's posttrans copies them to /var/lib/grafana/plugins-bundled,
# which grafana-server.service has grafana load. The rpm's copy moves there in place of that one, so
# the image carries the plugins once. Of the datasources, only the two the provisioned ones use
# stay, influxdb and prometheus: with the login form and basic auth off, no one can add another,
# and most of the others link a Go or golang.org/x/net older than its fixes. canvas, a panel with no
# binary, stays too, since grafana logs an error at every start without it. The influxdb 13.3.0
# bundles, 13.1.7, is built with go1.26.7 and x/net 0.58.0 as well; 13.1.10, the newest release,
# replaces it, pinned by the sha256 grafana.com publishes for it. config_grafana keeps grafana from
# fetching newer releases itself.
GRAFANA_PLUGINS := /var/lib/grafana/plugins-bundled
GRAFANA_UNUSED_PLUGINS := cloudwatch elasticsearch grafana-postgresql-datasource \
	grafana-pyroscope-datasource jaeger loki mssql mysql opentsdb stackdriver tempo zipkin
GRAFANA_INFLUXDB_VER := 13.1.10
GRAFANA_INFLUXDB_SHA256 := 01f73b902e3d5d2e061a214f60492dc4fe8b29a35648353e07eb55372a081769
GRAFANA_INFLUXDB_ZIP := $(ARCS_DIR)/grafana-influxdb-$(GRAFANA_INFLUXDB_VER).linux-amd64.zip

# .part then rename, as for elk.mk's jars
$(GRAFANA_INFLUXDB_ZIP):
	$(Q)mkdir -p $(@D)
	$(Q)wget 'https://grafana.com/api/plugins/influxdb/versions/$(GRAFANA_INFLUXDB_VER)/download?os=linux&arch=amd64' -O $@.part
	$(Q)echo "$(GRAFANA_INFLUXDB_SHA256)  $@.part" | sha256sum -c -
	$(Q)mv $@.part $@

rootfs_install:: $(GRAFANA_INFLUXDB_ZIP)
	$(Q)rm -rf $(ROOTDIR)$(GRAFANA_PLUGINS)
	$(Q)mv $(ROOTDIR)/usr/share/grafana/data/plugins-bundled $(ROOTDIR)$(GRAFANA_PLUGINS)
	$(Q)cd $(ROOTDIR)$(GRAFANA_PLUGINS) && rm -rf influxdb $(GRAFANA_UNUSED_PLUGINS) && unzip -q $<
	$(Q)chroot $(ROOTDIR) chown -R grafana:grafana $(GRAFANA_PLUGINS)

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
