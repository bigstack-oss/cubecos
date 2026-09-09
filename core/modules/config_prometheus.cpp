// CUBE SDK

#include <fcntl.h>
#include <unistd.h>

#include <hex/log.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <hex/logrotate.h>

#include <cube/systemd_util.h>

#include <string>
#include <utility>
#include <vector>

#include <filesystem.hpp>

#include "include/role_cubesys.h"

static const char NAME[] = "prometheus";

#define DEFCONF "/etc/default/prometheus"
#define DATADIR  "/var/lib/prometheus/data"
#define PORT "9091"

#define CONF "/etc/prometheus/prometheus.yml"
#define LACHESIS_TARGETS "/etc/prometheus/targets/lachesis.json"
#define LACHESIS_TARGETS_CRON "/etc/cron.d/lachesis_targets"
// the agent applies kernel deltas every 10s; the 60s global is coarse for it
#define LACHESIS_SCRAPE_INTERVAL "30s"
#define SCRAPE_INTERVAL "60s"
#define EVA_INTERVAL "60s"
#define QUERY_LOG "/var/log/prometheus/query.log"

// Thanos. The sidecar exports the local Prometheus over the Store API; the querier fans
// out to every control node's sidecar and deduplicates by the replica external label, so
// a node that was down and has come back no longer answers from its own gap.
//
// Ports: the sidecar keeps thanos's own defaults, the querier is moved off them because
// both binaries default to 10901/10902 and they share a host here.
#define THANOS_SIDECAR "thanos-sidecar"
#define THANOS_QUERY "thanos-query"
#define THANOS_SIDECAR_DEF "/etc/default/thanos-sidecar"
#define THANOS_QUERY_DEF "/etc/default/thanos-query"
#define THANOS_ENDPOINTS "/etc/thanos/endpoints.yml"
#define THANOS_SIDECAR_GRPC "10901"
#define THANOS_SIDECAR_HTTP "10902"
#define THANOS_QUERY_GRPC "10903"
#define THANOS_QUERY_HTTP "10904"
// the label that tells one replica's series from another's, and the one the querier
// strips when it deduplicates -- so a query answers exactly as it did before Thanos
#define THANOS_REPLICA_LABEL "replica"
// Object storage. The sidecar ships each finished block to ceph RGW, the store gateway
// serves those blocks back to the querier, and the compactor downsamples and enforces
// retention there. Without the store gateway the querier would only ever see what each
// prometheus still holds locally, so anything past local retention would be unreachable
// even though it is safely in the bucket.
#define THANOS_STORE "thanos-store"
#define THANOS_COMPACT "thanos-compact"
#define THANOS_STORE_DEF "/etc/default/thanos-store"
#define THANOS_COMPACT_DEF "/etc/default/thanos-compact"
#define THANOS_OBJSTORE "/etc/thanos/objstore.yml"
#define THANOS_BUCKET "thanos"
// rgw's beast frontend, and haproxy's radosgw_proxy in front of it (config_ceph,
// config_haproxy). Same port config_swift publishes as the object-store endpoint.
#define RGW_PORT "8888"
#define THANOS_STORE_GRPC "10905"
#define THANOS_STORE_HTTP "10906"
#define THANOS_COMPACT_HTTP "10907"
// Scratch for downsampling. On the root filesystem, not /store -- /store is the
// cross-version upgrade share, not a working directory. thanos has no flag that caps
// this directory, so what bounds it is the concurrency defaults (all 1, one compaction
// group at a time); /var/lib is already covered by the cube_disk_stats telegraf input.
#define THANOS_STORE_DATADIR   "/var/lib/thanos/store"
#define THANOS_COMPACT_DATADIR "/var/lib/thanos/compact"

// Exporters. What each one replaces from monasca-agent, and why the ports look like this:
//
//   node_exporter      cpu/load/mem/network/disk plugins, and Watcher's host_cpu_usage and
//                      host_ram_usage. Registered port 9100 is taken by CubeCOS haproxy's
//                      stats listener (config_haproxy.cpp, "listen stats"), and moving that
//                      would change an operator-facing URL, so the exporter moves instead.
//   blackbox_exporter  the http_check plugin, whose http_status series the six health_*_check
//                      functions read. Loopback: each control node's Prometheus uses its own.
//   ipmi_exporter      the ipmi_sensors plugin, and the only source on the box for Watcher's
//                      host_inlet_temp / host_outlet_temp / host_airflow / host_power.
//   memcached_exporter the mcache plugin.   apache_exporter  the apache plugin.
//
// haproxy, rabbitmq, influxdb and zookeeper are absent on purpose -- they all speak Prometheus
// natively, so there is nothing to install or run for them. See core/exporters/exporters.mk.
#define NODE_EXPORTER "prometheus-node-exporter"
#define NODE_EXPORTER_DEF "/etc/default/prometheus-node-exporter"
// The textfile collector's directory. node_exporter reads every *.prom in here on each
// scrape, which is how the per-instance metrics Watcher needs reach Prometheus without a
// separate exporter, port or scrape job -- this node's target already carries the fqdn
// label. The file itself is written by `hex_sdk watcher_instance_metrics`, which
// config_nova.cpp crons on compute-capable nodes -- that is where the domains are. Keep
// this path in step with that function's default.
#define NODE_TEXTFILE_DIR "/var/lib/node_exporter/textfile"
#define NODE_EXPORTER_PORT "9101"
#define BLACKBOX_EXPORTER "blackbox_exporter"
#define BLACKBOX_EXPORTER_DEF "/etc/default/blackbox_exporter"
#define BLACKBOX_EXPORTER_PORT "9115"
#define BLACKBOX_CONF "/etc/prometheus/exporters/blackbox.yml"
#define IPMI_EXPORTER "ipmi_exporter"
#define IPMI_EXPORTER_DEF "/etc/default/ipmi_exporter"
#define IPMI_EXPORTER_PORT "9290"
#define MEMCACHED_EXPORTER "memcached_exporter"
#define MEMCACHED_EXPORTER_DEF "/etc/default/memcached_exporter"
#define MEMCACHED_EXPORTER_PORT "9150"
#define APACHE_EXPORTER "apache_exporter"
#define APACHE_EXPORTER_DEF "/etc/default/apache_exporter"
#define APACHE_EXPORTER_PORT "9117"
// httpd's own default vhost, which is where mod_status lives. NOT port 80 -- that is the
// front-end proxy, and it answers /server-status with a 302 to https, which the exporter
// reports as apache_up 0 rather than as an error. config_apache2 ships the Location block
// (server-status.conf, Require local) already; only the port needed finding.
#define APACHE_STATUS_PORT "8080"
// haproxy's own promex service, on the stats listeners config_haproxy already binds. There
// are two, and they are different haproxies: the local one runs on every control node and
// fronts that node's own traffic (haproxy.cfg, :9100), while the -ha one is the pacemaker
// singleton that owns the VIP (haproxy-ha.cfg, :9000). Both are worth scraping and neither
// substitutes for the other.
#define HAPROXY_STATS_PORT "9100"
#define HAPROXY_HA_STATS_PORT "9000"
#define EXPORTER_TARGETS_CRON "/etc/cron.d/prometheus_exporter_targets"
#define NODE_TARGETS "/etc/prometheus/targets/node.json"
#define IPMI_TARGETS "/etc/prometheus/targets/ipmi.json"
#define MEMCACHED_TARGETS "/etc/prometheus/targets/memcached.json"
#define APACHE_TARGETS "/etc/prometheus/targets/apache.json"
// rabbitmq speaks Prometheus itself once the shipped rabbitmq_prometheus plugin is enabled,
// which config_rabbitmq now does, so there is no exporter to install or run -- only a target
// list.
//
// Zookeeper looked like the same win and is not, which is worth recording so it is not
// re-attempted: 3.8 does carry a PrometheusMetricsProvider, but the class lives in
// zookeeper-prometheus-metrics.jar and Kafka's bundled distribution ships only
// zookeeper.jar and zookeeper-jute.jar, so configuring it makes zookeeper exit with
// INVALIDARGUMENT. It needs prometheus/jmx_exporter, as does kafka, which has no native
// endpoint at all -- one artifact covering both, in a separate change.
#define RABBITMQ_TARGETS "/etc/prometheus/targets/rabbitmq.json"
// influxdb is scraped for what it will report, not what it reports today. 1.12's /metrics
// is 116 lines of go_*, process_* and promhttp_* with not one influx-specific series -- no
// shards, no series counts, no writes, no queries, because 1.x keeps those in the _internal
// database. 2.x exposes them properly, and issue #648 moves us there; wiring the job now
// means that lands with no further change here. Until then it costs one scrape and reports
// influxd's garbage collector.
#define INFLUXDB_TARGETS "/etc/prometheus/targets/influxdb.json"

static CubeRole_e s_eCubeRole;

static bool s_bCubeModified = false;
static bool s_bNetModified = false;

static ConfigString s_hostname;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("prometheus", "/var/log/prometheus/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(SHARED_ID);
// the node's own management address: the store gateway's http port binds to it so
// health_thanos_check can reach it from any control node, without offering it on every
// interface the way 0.0.0.0 would
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);

// Retention, tunable so a cluster can be sized without a rebuild.
//
// Both limits apply and whichever is reached first wins, which is the point: time
// alone does not bound disk if cardinality grows, and 90d with no size cap was the
// same unbounded shape as influxdb's 364d -- on the same system partition as the OS,
// ceph and the influx TSDB.
//
// Size 0 disables the size limit (prometheus's own semantics), and the flag is then
// omitted entirely rather than written as 0.
//
// Note prometheus counts in powers of two: its "GB" is 1024^3, so 5GB here is 5 GiB
// and prometheus echoes it back as "5GiB".
CONFIG_TUNING_INT(PROMETHEUS_RP_DAYS, "prometheus.rp.duration", TUNING_PUB, "prometheus retention duration in days.", 30, 1, 3650);
CONFIG_TUNING_INT(PROMETHEUS_RP_SIZE, "prometheus.rp.size", TUNING_PUB, "prometheus retention size cap in GiB, 0 to disable.", 5, 0, 10240);
// Retention in object storage, enforced by the compactor rather than by any RGW
// lifecycle rule: expiry that thanos does not know about leaves dangling block
// metadata behind. Applied to all three resolutions, so 90d means 90d of history
// whatever its resolution.
CONFIG_TUNING_INT(THANOS_RP_DAYS, "prometheus.thanos.rp.duration", TUNING_PUB, "thanos object storage retention in days.", 90, 1, 3650);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);

// parse tunings
PARSE_TUNING_INT(s_rpDays, PROMETHEUS_RP_DAYS);
PARSE_TUNING_INT(s_rpSize, PROMETHEUS_RP_SIZE);
PARSE_TUNING_INT(s_thanosRpDays, THANOS_RP_DAYS);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);

static bool
WriteDefaultConf(const std::string& myIp)
{
    FILE *fout = fopen(DEFCONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s default file: %s", NAME, DEFCONF);
        return false;
    }

    // ARGS, not PROMETHEUS_OPTS: EPEL's prometheus unit is ExecStart=/usr/bin/prometheus $ARGS.
    // (packagecloud's retired prometheus2 unit used $PROMETHEUS_OPTS.)
    //
    // Retention is not passed here. Both --storage.tsdb.retention.time and .size
    // are marked [DEPRECATED] in 3.13, which points at the config file's
    // storage.tsdb.retention block instead, and a flag set here would take
    // precedence over that block -- silently pinning the value and making the
    // tunings look ineffective. WriteConf emits the block; this file only carries
    // the flags that have no config-file equivalent.
    // max-block-duration = min-block-duration disables prometheus's own compaction,
    // which the thanos sidecar REQUIRES before it will upload anything. It validates
    // this itself and refuses loudly rather than shipping bad blocks -- observed:
    // "found that TSDB Max time is 3d and Min time is 2h. Compaction needs to be
    // disabled". Prometheus derives max as 10% of retention when unset, so this is not
    // a constant that can be left alone: cutting retention to 30d moved it to 3d.
    fprintf(fout, "ARGS='--config.file=" CONF
                  " --storage.tsdb.path=" DATADIR
                  " --storage.tsdb.max-block-duration=2h"
                  " --storage.tsdb.min-block-duration=2h"
                  " --web.external-url=http://localhost/prometheus/");
    // Prometheus is the one listener that needs both. Loopback is what the thanos
    // sidecar, the self-scrape job and the non-HA haproxy backend all use; the
    // management address is what health_prometheus_check probes from another control
    // node. The flag is documented "Can be repeated" and 3.13 binds both.
    fprintf(fout, " --web.listen-address=127.0.0.1:" PORT
                  " --web.listen-address=%s:" PORT "'\n", myIp.c_str());
    fclose(fout);

    return true;
}

static bool
WriteConf(bool ha, const std::string& sharedId, const std::string& ctrlAddrs,
          const std::string& hostname, int rpDays, int rpSizeGib)
{
    FILE *fout = fopen(CONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s conf file: %s", NAME, CONF);
        return false;
    }

    // storage.tsdb.retention rather than the command-line flags: 3.13 marks both
    // --storage.tsdb.retention.time and .size [DEPRECATED] and names this block as
    // the replacement. Time and size are both enforced, whichever is reached first
    // -- time alone does not bound disk if cardinality grows.
    //
    // This block requires prometheus 3.x; a 2.x prometheus refuses to parse the file
    // rather than ignoring the unknown field ("field retention not found in type
    // config.plain"), so it must not be emitted for a 2.x install. This branch ships
    // 3.13 from EPEL, so that case cannot arise here.
    fprintf(fout, "storage:\n");
    fprintf(fout, "  tsdb:\n");
    fprintf(fout, "    retention:\n");
    fprintf(fout, "      time: %dd\n", rpDays);
    if (rpSizeGib > 0)
        fprintf(fout, "      size: %dGB\n", rpSizeGib);   // prometheus GB is 1024^3

    fprintf(fout, "global:\n");
    // The replica label is what lets Thanos tell one control node's copy of a series from
    // another's, and what its querier strips when deduplicating. It is not optional: the
    // sidecar refuses to start against a Prometheus with no external labels at all.
    // Harmless without Thanos -- it is one more label on every series, matched by nobody.
    fprintf(fout, "  external_labels:\n");
    fprintf(fout, "    " THANOS_REPLICA_LABEL ": %s\n", hostname.c_str());
    fprintf(fout, "  scrape_interval: " SCRAPE_INTERVAL "\n");
    fprintf(fout, "  evaluation_interval: " EVA_INTERVAL "\n");
    fprintf(fout, "  query_log_file: " QUERY_LOG "\n");
    fprintf(fout, "scrape_configs:\n");
    // metrics_path has to carry the route prefix. The --web.external-url set in
    // WriteDefaultConf ends in /prometheus/, and prometheus derives --web.route-prefix from
    // it, so it serves its own /metrics at /prometheus/metrics and answers a bare /metrics
    // with 404. Without this the self-scrape has always been down
    // (up{job="prometheus"}=0 on every node), which is why no prometheus_* series existed
    // to monitor prometheus with.
    //
    // The prefix cannot simply be dropped instead: haproxy's prometheus_backend forwards the
    // path unchanged (no replace-path), so prometheus must keep serving under /prometheus for
    // the UI and Grafana to reach it.
    fprintf(fout, "  - job_name: 'prometheus'\n");
    fprintf(fout, "    metrics_path: /prometheus/metrics\n");
    fprintf(fout, "    static_configs:\n");
    fprintf(fout, "    - targets: ['localhost:9091']\n");
    fprintf(fout, "  - job_name: 'ceph'\n");
    fprintf(fout, "    static_configs:\n");
    if (ha)
        fprintf(fout, "    - targets: ['%s:9285']\n", sharedId.c_str());
    else
        fprintf(fout, "    - targets: ['%s:9283']\n", sharedId.c_str());

    // lachesis, one agent per compute node. file_sd not static_configs: this
    // module does not re-commit when compute membership changes, and prometheus
    // reloads file_sd on its own. A missing file is not an error.
    fprintf(fout, "  - job_name: 'lachesis-agent'\n");
    fprintf(fout, "    scrape_interval: " LACHESIS_SCRAPE_INTERVAL "\n");
    fprintf(fout, "    file_sd_configs:\n");
    fprintf(fout, "    - files:\n");
    fprintf(fout, "      - '" LACHESIS_TARGETS "'\n");

    // The exporter jobs. file_sd for everything that is per-node, because compute and
    // storage membership is not in cubesys.control.addrs and a node joining must not need a
    // commit to be scraped; the generator stamps each target with the fqdn label whose value
    // is that node's hostname, which is what Watcher's host metrics are keyed on.
    const std::vector<std::pair<std::string, std::string>> sdJobs = {
        { "node",      NODE_TARGETS },
        { "ipmi",      IPMI_TARGETS },
        { "memcached", MEMCACHED_TARGETS },
        { "apache",    APACHE_TARGETS },
        { "rabbitmq",  RABBITMQ_TARGETS },
        { "influxdb",  INFLUXDB_TARGETS },
    };
    for (const auto& job : sdJobs) {
        fprintf(fout, "  - job_name: '%s'\n", job.first.c_str());
        fprintf(fout, "    file_sd_configs:\n");
        fprintf(fout, "    - files:\n");
        fprintf(fout, "      - '%s'\n", job.second.c_str());
    }

    // haproxy needs no exporter -- see HAPROXY_STATS_PORT. The per-node local instance is
    // listed from cubesys.control.addrs rather than file_sd, because haproxy only runs where
    // Prometheus does and that list is already observed by this module.
    fprintf(fout, "  - job_name: 'haproxy'\n");
    fprintf(fout, "    static_configs:\n");
    auto haGroup = hex_string_util::split(ctrlAddrs, ',');
    for (const auto& addr : haGroup)
        fprintf(fout, "    - targets: ['%s:" HAPROXY_STATS_PORT "']\n", addr.c_str());

    // The VIP instance is a separate haproxy on a separate port, and a separate job so its
    // series are not mixed in with the per-node ones. Only exists on HA.
    if (ha) {
        fprintf(fout, "  - job_name: 'haproxy-ha'\n");
        fprintf(fout, "    static_configs:\n");
        fprintf(fout, "    - targets: ['%s:" HAPROXY_HA_STATS_PORT "']\n", sharedId.c_str());
    }

    // blackbox is a probe runner, so the job lists what to probe and hands each target to
    // the exporter as a parameter rather than scraping it directly. These are the same
    // service ports config_haproxy fronts, reached through the VIP, which is what monasca's
    // http_check watched -- so this is the series the six health_*_check functions read.
    //
    // Each target carries a service label, because that is how the consumer asks. monasca
    // dimensioned http_status by service and the checks selected on it; keeping a label
    // means the query stays a name lookup instead of a port number the reader has to
    // recognise, and a port move here does not silently break sdk_health.sh. The names are
    // CubeCOS's own -- the ones the health_*_check functions are named after -- rather than
    // monasca's "image-service"/"block-storage", which belonged to its dimension vocabulary
    // and to nothing that outlives it.
    const std::vector<std::pair<std::string, std::string>> probes = {
        { "nova",      "8774" },
        { "glance",    "9292" },
        { "cinder",    "8776" },
        { "heat",      "8004" },
        { "octavia",   "9876" },
        { "designate", "9001" },
    };
    fprintf(fout, "  - job_name: 'blackbox-openstack'\n");
    fprintf(fout, "    metrics_path: /probe\n");
    fprintf(fout, "    params:\n");
    fprintf(fout, "      module: [openstack_api]\n");
    fprintf(fout, "    static_configs:\n");
    for (const auto& probe : probes) {
        fprintf(fout, "    - targets: ['http://%s:%s/']\n", sharedId.c_str(), probe.second.c_str());
        fprintf(fout, "      labels:\n");
        fprintf(fout, "        service: %s\n", probe.first.c_str());
    }
    // __address__ has to become the exporter and the original target has to survive as a
    // label, or every series would be labelled with the exporter instead of the service.
    fprintf(fout, "    relabel_configs:\n");
    fprintf(fout, "    - source_labels: [__address__]\n");
    fprintf(fout, "      target_label: __param_target\n");
    fprintf(fout, "    - source_labels: [__param_target]\n");
    fprintf(fout, "      target_label: instance\n");
    fprintf(fout, "    - target_label: __address__\n");
    fprintf(fout, "      replacement: 127.0.0.1:" BLACKBOX_EXPORTER_PORT "\n");

    fclose(fout);

    return true;
}

// Sidecar endpoints for the querier, one per control node. Written from
// cubesys.control.addrs, which this module already observes, so a control-membership
// change re-commits and rewrites the list -- unlike the lachesis compute list below,
// which needs a cron because compute membership does not re-commit anything.
//
// The /etc/default/ARGS lines for the exporters this node runs. Written on every role, not
// just control: node_exporter and ipmi_exporter report on compute and storage nodes too, and
// the Prometheus that scrapes them lives elsewhere.
//
// Each binds one address rather than 0.0.0.0, the same rule the thanos ports follow: the
// management address where a Prometheus on another node scrapes it, loopback where only the
// local one does.
static bool
WriteExporterDefaults(bool control, const std::string& myIp)
{
    std::string fsError;

    const std::vector<std::string> node = {
        "ARGS='--web.listen-address=" + myIp + ":" NODE_EXPORTER_PORT
        " --collector.textfile.directory=" NODE_TEXTFILE_DIR "'\n",
    };
    if (!WriteFile(fsError, NODE_EXPORTER_DEF, node)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    // freeipmi's local path needs no host argument; without a config file the exporter uses
    // its built-in "default" collector against the local BMC, which is what the monasca
    // plugin did. A VM lab has no BMC and every probe fails -- the series read as down, same
    // as they did before.
    const std::vector<std::string> ipmi = {
        "ARGS='--web.listen-address=" + myIp + ":" IPMI_EXPORTER_PORT "'\n",
    };
    if (!WriteFile(fsError, IPMI_EXPORTER_DEF, ipmi)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    if (!control)
        return true;

    // Loopback: the only client is this node's own Prometheus, and a probe target list is a
    // fine thing not to expose. It is the *probe* that reaches across the cluster, not this.
    const std::vector<std::string> blackbox = {
        "ARGS='--config.file=" BLACKBOX_CONF
        " --web.listen-address=127.0.0.1:" BLACKBOX_EXPORTER_PORT "'\n",
    };
    if (!WriteFile(fsError, BLACKBOX_EXPORTER_DEF, blackbox)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    const std::vector<std::string> memcached = {
        "ARGS='--memcached.address=127.0.0.1:11211"
        " --web.listen-address=" + myIp + ":" MEMCACHED_EXPORTER_PORT "'\n",
    };
    if (!WriteFile(fsError, MEMCACHED_EXPORTER_DEF, memcached)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    // mod_status is exposed on localhost only by config_apache2, so the scrape URI is
    // loopback even though the exporter itself is reachable on the management address.
    // The port is httpd's own vhost, not 80 -- see APACHE_STATUS_PORT.
    const std::vector<std::string> apache = {
        "ARGS='--scrape_uri=http://127.0.0.1:" APACHE_STATUS_PORT "/server-status?auto"
        " --web.listen-address=" + myIp + ":" APACHE_EXPORTER_PORT "'\n",
    };
    if (!WriteFile(fsError, APACHE_EXPORTER_DEF, apache)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    return true;
}

// Membership changes do not re-commit this module, so the per-node target lists are kept
// current by cron -- the same arrangement, and the same reasoning, as the lachesis list.
//
// WriteFile rather than fopen, for the mode: a bare fopen leaves it to the process umask,
// which CodeQL reports as cpp/world-writable-file-creation and which cron would refuse to
// run anyway if the umask ever let the file out group-writable. Same fix as the thanos
// config files a few commits back, and as config_apache2 before them.
static bool
WriteExporterTargetsCronJob()
{
    std::string fsError;

    const std::vector<std::string> cron = {
        "* * * * * root " HEX_SDK " prometheus_exporter_targets\n",
    };
    if (!WriteFile(fsError, EXPORTER_TARGETS_CRON, cron)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    return true;
}

// The schema is thanos's own EndpointConfig, not prometheus file_sd: a bare list of
// targets parses and then silently discovers nothing.
static bool
WriteThanosConf(const std::string& ctrlAddrs, const std::string& sharedId, int thanosRpDays)
{
    std::string fsError;
    // Every listener below binds either this or loopback -- never 0.0.0.0. A thanos port
    // is reachable off-box only where something off-box actually calls it.
    const std::string myIp = G(MGMT_ADDR);

    // The bucket, its native rgw user and the credentials file thanos reads. Done in the
    // sdk because it needs radosgw-admin and s3cmd; idempotent, so it runs every commit.
    //
    // The endpoint is passed rather than discovered. os_endpoint.snapshot is the obvious
    // source but is not written until cube_last, six levels after this module, and on a
    // master's first bootstrap keystone skips writing it too -- so at L12 it is routinely
    // absent and thanos would come up with no objstore config at all. <shared_id>:8888 is
    // the same internal endpoint config_swift registers, and it only needs rgw (ceph, L11)
    // and haproxy's radosgw_proxy (L10), both of which this module already sorts after.
    HexUtilSystemF(0, 120, HEX_SDK " thanos_objstore_setup %s:%s %s",
                   sharedId.c_str(), RGW_PORT, THANOS_BUCKET);

    // Every sidecar, plus this node's store gateway. Without the store gateway entry the
    // querier sees only what the prometheis still hold locally.
    std::vector<std::string> endpoints = { "endpoints:\n" };
    auto group = hex_string_util::split(ctrlAddrs, ',');
    for (const auto& addr : group)
        endpoints.push_back("- address: " + addr + ":" THANOS_SIDECAR_GRPC "\n");
    endpoints.push_back("- address: 127.0.0.1:" THANOS_STORE_GRPC "\n");

    if (!WriteFile(fsError, THANOS_ENDPOINTS, endpoints)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    // prometheus.url carries the route prefix: --web.external-url puts every endpoint,
    // /api included, under /prometheus, and the sidecar talks to it over that API.
    //
    // gRPC binds the management address: every control node's querier dials this node's
    // sidecar, which is the endpoints.yml list written above. The HTTP port carries only
    // readiness and metrics and nothing reads it -- the health check establishes sidecar
    // liveness through systemd, not over HTTP -- so it stays on loopback.
    const std::vector<std::string> sidecar = {
        "ARGS='--prometheus.url=http://127.0.0.1:" PORT "/prometheus"
        " --tsdb.path=" DATADIR
        " --objstore.config-file=" THANOS_OBJSTORE
        " --grpc-address=" + myIp + ":" THANOS_SIDECAR_GRPC
        " --http-address=127.0.0.1:" THANOS_SIDECAR_HTTP "'\n",
    };
    if (!WriteFile(fsError, THANOS_SIDECAR_DEF, sidecar)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    // Serves under the same /prometheus prefix the raw Prometheus did, so haproxy's route
    // and grafana's datasource keep working when the backend moves here. Note thanos keeps
    // /-/ready and /-/healthy at the root regardless -- that is what haproxy checks.
    //
    // HTTP binds the management address: haproxy lists every control node as a backend
    // for this port and health_thanos_check probes it across nodes. The gRPC port would
    // matter if a querier fanned out to another querier, or if thanos-rule existed here;
    // neither does, so nothing dials it and it stays on loopback.
    const std::vector<std::string> query = {
        "ARGS='--endpoint.sd-config-file=" THANOS_ENDPOINTS
        " --query.replica-label=" THANOS_REPLICA_LABEL
        " --grpc-address=127.0.0.1:" THANOS_QUERY_GRPC
        " --http-address=" + myIp + ":" THANOS_QUERY_HTTP
        " --web.route-prefix=/prometheus"
        " --web.external-prefix=/prometheus'\n",
    };
    if (!WriteFile(fsError, THANOS_QUERY_DEF, query)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    // Neither port is offered on every interface. The store gateway is only ever
    // consulted by the querier on its own node -- that is the 127.0.0.1 entry written
    // above -- so gRPC binds loopback. Its HTTP port serves only readiness and metrics,
    // but health_thanos_check probes it from whichever control node runs the check, so
    // it binds the management address rather than 0.0.0.0. Contrast the sidecar, whose
    // gRPC port every node's querier dials, and the querier, which sits behind haproxy.
    const std::vector<std::string> store = {
        "ARGS='--objstore.config-file=" THANOS_OBJSTORE
        " --data-dir=" THANOS_STORE_DATADIR
        " --grpc-address=127.0.0.1:" THANOS_STORE_GRPC
        " --http-address=" + myIp + ":" THANOS_STORE_HTTP "'\n",
    };
    if (!WriteFile(fsError, THANOS_STORE_DEF, store)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    // --wait keeps the compactor running as a service instead of doing one pass and
    // exiting. Retention is applied to all three resolutions, so the tuning means
    // "keep this much history" regardless of how coarse it has been downsampled to.
    // Concurrency is left at thanos's defaults (all 1): there is no flag that caps
    // --data-dir, and one compaction group at a time is what keeps it bounded.
    //
    // Loopback, and unlike the store gateway not even the management address: nothing
    // reads this port. The compactor exposes no gRPC at all -- no querier talks to it --
    // and health_thanos_check establishes the singleton by asking every node whether the
    // unit is active, which is what pacemaker actually places, rather than by probing an
    // address it would first have to discover.
    const std::string rp = std::to_string(thanosRpDays) + "d";
    const std::vector<std::string> compact = {
        "ARGS='--objstore.config-file=" THANOS_OBJSTORE
        " --data-dir=" THANOS_COMPACT_DATADIR
        " --wait"
        " --retention.resolution-raw=" + rp +
        " --retention.resolution-5m=" + rp +
        " --retention.resolution-1h=" + rp +
        " --http-address=127.0.0.1:" THANOS_COMPACT_HTTP "'\n",
    };
    if (!WriteFile(fsError, THANOS_COMPACT_DEF, compact)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    return true;
}

// same shape as glance's export-sync and influxdb's curator cron jobs
static bool
WriteLachesisTargetsCronJob(void)
{
    int fd = open(LACHESIS_TARGETS_CRON, O_CREAT | O_WRONLY | O_TRUNC,
                  S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
    if (fd == -1) {
        HexLogError("Unable to open file %s", LACHESIS_TARGETS_CRON);
        return false;
    }
    FILE* fout = fdopen(fd, "w");
    if (!fout) {
        HexLogError("Unable to write lachesis target cron job: %s", LACHESIS_TARGETS_CRON);
        close(fd);
        return false;
    }

    fprintf(fout, "* * * * * root " HEX_SDK " lachesis_prometheus_targets\n");
    fclose(fout);

    if (HexSetFileMode(LACHESIS_TARGETS_CRON, "root", "root", 0644) != 0) {
        HexLogError("Unable to set file %s mode/permission", LACHESIS_TARGETS_CRON);
        return false;
    }

    return true;
}

static bool
ParseCube(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 1);
    return true;
}

static void
NotifyCube(bool modified)
{
    s_bCubeModified = IsModifiedTune(1);
    s_eCubeRole = GetCubeRole(s_cubeRole);
}

static bool
ParseNet(const char *name, const char *value, bool isNew)
{
    if (strcmp(name, NET_HOSTNAME) == 0) {
        s_hostname.parse(value, isNew);
    }

    return true;
}

static void
NotifyNet(bool modified)
{
    s_bNetModified = s_hostname.modified();
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        return true;
    }

    return s_bCubeModified | s_bNetModified | G_MOD(SHARED_ID) | G_MOD(MGMT_ADDR);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = IsControl(s_eCubeRole);
    // Thanos only earns its keep where there is more than one replica to reconcile. On a
    // single control node the querier would fan out to one sidecar and dedupe nothing, so
    // both stay off and /prometheus keeps pointing straight at the local Prometheus.
    bool thanosEnabled = enabled && s_ha;
    std::string sharedId = G(SHARED_ID);
    std::string hostname = s_hostname.newValue();

    // The exporters are not gated on `enabled`. Prometheus itself only runs on control
    // nodes, but node_exporter and ipmi_exporter report on compute and storage nodes too --
    // that is the whole point of them -- so their config and their units are handled on
    // every role, and only the scrape side below is control-only.
    WriteExporterDefaults(enabled, G(MGMT_ADDR));
    SystemdCommitService(true, NODE_EXPORTER);
    SystemdCommitService(true, IPMI_EXPORTER);
    SystemdCommitService(enabled, BLACKBOX_EXPORTER);
    SystemdCommitService(enabled, MEMCACHED_EXPORTER);
    SystemdCommitService(enabled, APACHE_EXPORTER);

    if (enabled) {
        WriteDefaultConf(G(MGMT_ADDR));
        WriteConf(s_ha, sharedId, s_ctrlAddrs.newValue(), hostname,
                  s_rpDays.newValue(), s_rpSize.newValue());

        // seed the target lists; non-fatal, and bounded so a wedged etcd
        // cannot hang the commit
        HexUtilSystemF(0, 30, HEX_SDK " lachesis_prometheus_targets");
        HexUtilSystemF(0, 30, HEX_SDK " prometheus_exporter_targets");
        WriteExporterTargetsCronJob();

        // membership changes (node join/remove) do not re-commit this module,
        // so a cron keeps the list current; the generator only rewrites the
        // file when membership actually changed
        WriteLachesisTargetsCronJob();

        log_conf.postRotateCmds = "killall -HUP prometheus";
        WriteLogRotateConf(log_conf);
    }
    else {
        unlink(LACHESIS_TARGETS_CRON);
        unlink(EXPORTER_TARGETS_CRON);
    }

    if (thanosEnabled)
        WriteThanosConf(s_ctrlAddrs.newValue(), sharedId, s_thanosRpDays.newValue());

    SystemdCommitService(enabled, NAME);
    // after prometheus: the sidecar exits if it cannot reach it, and while Restart=always
    // covers that, starting in order keeps a boot from logging the failure at all
    SystemdCommitService(thanosEnabled, THANOS_SIDECAR);
    SystemdCommitService(thanosEnabled, THANOS_QUERY);
    SystemdCommitService(thanosEnabled, THANOS_STORE);

    // thanos-compact is pacemaker's to place -- two of them on one bucket corrupt it --
    // so it is never enabled here. config_pacemaker masks it before pacemaker comes up;
    // unmasking once its config exists is this module's half of that handshake, and
    // pacemaker creates the resource later still, from CommitLast.
    if (thanosEnabled)
        HexUtilSystemF(0, 0, "systemctl unmask " THANOS_COMPACT);

    return true;
}

CONFIG_MODULE(prometheus, 0, 0, 0, 0, Commit);
CONFIG_REQUIRES(prometheus, cube_scan);
// thanos_objstore_setup needs a working RGW to create its user and bucket, and ceph is
// what brings radosgw up. Without this prometheus commits at L8, three levels ahead of
// ceph at L11, and the bootstrap would run against an object store that does not exist.
CONFIG_REQUIRES(prometheus, ceph);

// extra tunings
CONFIG_OBSERVES(prometheus, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(prometheus, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(prometheus, "/var/lib/prometheus");

