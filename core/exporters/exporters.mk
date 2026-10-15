# Cube SDK
# Prometheus exporter installation
#
# Every exporter is built from source in core/exporters/Makefile, at its upstream release tag,
# and installed from the build tree here. Not the packagecloud repo core/prometheus/prometheus.mk
# retired, which is stale for every exporter; and, until a release is built with a Go and
# golang.org/x modules that clear the scanner (cubecos#978, see the Makefile), neither the
# upstream tarballs nor EPEL's node-exporter rpm.
#
# Four services that would otherwise need an exporter are absent on purpose, because they
# already speak Prometheus and adding one would be pure overhead. Each was checked on a live
# node rather than assumed:
#
#   haproxy    2.8 is built +PROMEX ("Available services : prometheus-exporter"), so
#              config_haproxy exposes it with one use-service line on the stats listener it
#              already binds. No haproxy_exporter.
#   rabbitmq   3.12 ships rabbitmq_prometheus -- shipped DISABLED, so config_rabbitmq has to
#              enable it. "Speaks Prometheus" is not "is turned on".
#   influxdb   1.12 serves /metrics, though on 1.x it carries only go/process/promhttp series
#              and nothing about the database. Scraped anyway, because 2.x reports properly
#              and issue #648 moves us there.
#
# Zookeeper looked like the same win and is not, which is worth recording so it is not
# re-attempted: 3.8 has a PrometheusMetricsProvider, but Kafka's bundled distribution does
# not ship the jar it lives in. It needs jmx_exporter, as does kafka. See
# config_prometheus.cpp.
#
# Provenance matters -- these run as daemons on every node -- so each is either the prometheus
# org or prometheus-community, with one documented exception:
#
#   node_exporter       prometheus
#   blackbox_exporter   prometheus
#   memcached_exporter  prometheus
#   ipmi_exporter       prometheus-community  (moved off soundcloud/)
#   apache_exporter     Lusitaniae/           <- NOT org-backed. It is the exporter the official
#                       prometheus.io catalogue lists for Apache, actively maintained, and there
#                       is no org-backed alternative. It feeds Grafana middleware panels only --
#                       nothing Watcher or the health checks depend on -- so it is the one entry
#                       here that can be dropped without breaking a consumer.

# node_exporter's registered port is 9100, which CubeCOS haproxy already binds for its stats
# listener (config_haproxy.cpp, "listen stats"). Moving haproxy would change an operator-facing
# URL, so the exporter moves instead -- see NODE_EXPORTER_PORT in config_prometheus.cpp. Every
# other exporter keeps its registered default.
EXPORTER_BINS := blackbox_exporter ipmi_exporter memcached_exporter apache_exporter node_exporter
EXPORTER_BLDDIR := $(TOP_BLDDIR)/core/exporters
# node_exporter's unit keeps the name EPEL's rpm gave it, which config_prometheus.cpp enables.
EXPORTER_UNITS := $(filter-out node_exporter,$(EXPORTER_BINS)) prometheus-node-exporter

heavy_components_install:: $(foreach b,$(EXPORTER_BINS),$(EXPORTER_BLDDIR)/$(b))
	$(Q)$(foreach b,$(EXPORTER_BINS),$(INSTALL_PROGRAM) $(ROOTDIR) $(EXPORTER_BLDDIR)/$(b) ./usr/bin ;)
	# /etc/default holds only the directory here. The ARGS content is per-node -- it carries
	# the management address -- so it cannot be baked into the image, and config_prometheus.cpp
	# owns the write-then-enable ordering: it writes each /etc/default file before it enables
	# the corresponding unit, so a configured exporter never starts without one.
	$(Q)# node_exporter's textfile collector directory. Created here so the collector has
	$(Q)# somewhere to write on first boot; hex_sdk instance_metrics_collect fills it and
	$(Q)# config_prometheus points node_exporter at it.
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/prometheus/exporters /etc/default /var/lib/node_exporter/textfile
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/exporters/blackbox.yml ./etc/prometheus/exporters/
	$(Q)$(foreach u,$(EXPORTER_UNITS),$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/exporters/$(u).service ./lib/systemd/system ;)
	# Every exporter is installed disabled; config_prometheus.cpp enables the ones this node's
	# role actually has something to export, the same way it does for thanos. node_exporter and
	# ipmi_exporter end up enabled on every role, the rest only on control.
	$(Q)$(foreach u,$(EXPORTER_UNITS),chroot $(ROOTDIR) systemctl disable $(u) ;)
