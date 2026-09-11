# Cube SDK
# Prometheus exporter installation
#
# Sourcing is split, and deliberately not the packagecloud repo core/prometheus/prometheus.mk
# retired: it is stale for every exporter. EPEL carries node-exporter at the current upstream
# version and none of the others, and no upstream exporter publishes an rpm at all -- every one
# ships a linux-amd64.tar.gz and nothing else. So: one ROOTFS_DNF line here, and the tarballs
# fetched and digest-checked in core/exporters/Makefile like any other build artifact.
#
# Four services that would otherwise need an exporter are absent on purpose, because they
# already speak Prometheus and adding one would be pure overhead. Each was checked on a live
# node rather than assumed:
#
#   haproxy    2.8 is built +PROMEX ("Available services : prometheus-exporter"), so
#              config_haproxy exposes it with one use-service line on the stats listener it
#              already binds. No haproxy_exporter.
#   rabbitmq   3.11 ships rabbitmq_prometheus -- shipped DISABLED, so config_rabbitmq has to
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
#   node_exporter       prometheus            (via EPEL)
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
ROOTFS_DNF += node-exporter

EXPORTER_BINS := blackbox_exporter ipmi_exporter memcached_exporter apache_exporter
EXPORTER_BLDDIR := $(TOP_BLDDIR)/core/exporters

rootfs_install:: $(foreach b,$(EXPORTER_BINS),$(EXPORTER_BLDDIR)/$(b))
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
	$(Q)$(foreach b,$(EXPORTER_BINS),$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/exporters/$(b).service ./lib/systemd/system ;)
	# Every exporter is installed disabled; config_prometheus.cpp enables the ones this node's
	# role actually has something to export, the same way it does for thanos. node_exporter and
	# ipmi_exporter end up enabled on every role, the rest only on control.
	$(Q)$(foreach b,$(EXPORTER_BINS),chroot $(ROOTDIR) systemctl disable $(b) ;)
	# EPEL ships node-exporter with two unit names for the same binary. Only
	# prometheus-node-exporter is configured (it is the one carrying EnvironmentFile), so the
	# other is masked rather than left as a second way to start an unconfigured copy.
	$(Q)chroot $(ROOTDIR) systemctl disable prometheus-node-exporter
	$(Q)chroot $(ROOTDIR) systemctl mask node_exporter
