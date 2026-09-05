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

#include <filesystem.hpp>

#include "include/role_cubesys.h"

static const char NAME[] = "prometheus";

#define DEFCONF "/etc/default/prometheus"
#define DATADIR  "/var/lib/prometheus/data"
#define PORT "9091"
#define TSDB_RP "90d"

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

static CubeRole_e s_eCubeRole;

static bool s_bCubeModified = false;
static bool s_bNetModified = false;

static ConfigString s_hostname;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("prometheus", "/var/log/prometheus/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);

// parse tunings
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);

static bool
WriteDefaultConf()
{
    FILE *fout = fopen(DEFCONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s default file: %s", NAME, DEFCONF);
        return false;
    }

    // ARGS, not PROMETHEUS_OPTS: EPEL's prometheus unit is ExecStart=/usr/bin/prometheus $ARGS.
    // (packagecloud's retired prometheus2 unit used $PROMETHEUS_OPTS.)
    //
    // retention.time, not retention: the bare --storage.tsdb.retention has been deprecated
    // since 2.x and 3.13's own --help still marks it [DEPRECATED]. It is accepted today, but
    // there is no reason to keep feeding a flag upstream has been telling us to stop using.
    fprintf(fout, "ARGS='--config.file=" CONF
                  " --storage.tsdb.path=" DATADIR
                  " --storage.tsdb.retention.time=" TSDB_RP
                  " --web.external-url=http://localhost/prometheus/"
                  " --web.listen-address=:" PORT "'\n");
    fclose(fout);

    return true;
}

static bool
WriteConf(bool ha, const std::string& sharedId, const std::string& hostname)
{
    FILE *fout = fopen(CONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s conf file: %s", NAME, CONF);
        return false;
    }

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

    fclose(fout);

    return true;
}

// Sidecar endpoints for the querier, one per control node. Written from
// cubesys.control.addrs, which this module already observes, so a control-membership
// change re-commits and rewrites the list -- unlike the lachesis compute list below,
// which needs a cron because compute membership does not re-commit anything.
//
// The schema is thanos's own EndpointConfig, not prometheus file_sd: a bare list of
// targets parses and then silently discovers nothing.
static bool
WriteThanosConf(const std::string& ctrlAddrs)
{
    std::string fsError;

    std::vector<std::string> endpoints = { "endpoints:\n" };
    auto group = hex_string_util::split(ctrlAddrs, ',');
    for (const auto& addr : group)
        endpoints.push_back("- address: " + addr + ":" THANOS_SIDECAR_GRPC "\n");

    if (!WriteFile(fsError, THANOS_ENDPOINTS, endpoints)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    // prometheus.url carries the route prefix: --web.external-url puts every endpoint,
    // /api included, under /prometheus, and the sidecar talks to it over that API.
    const std::vector<std::string> sidecar = {
        "ARGS='--prometheus.url=http://127.0.0.1:" PORT "/prometheus"
        " --tsdb.path=" DATADIR
        " --grpc-address=0.0.0.0:" THANOS_SIDECAR_GRPC
        " --http-address=0.0.0.0:" THANOS_SIDECAR_HTTP "'\n",
    };
    if (!WriteFile(fsError, THANOS_SIDECAR_DEF, sidecar)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    // Serves under the same /prometheus prefix the raw Prometheus did, so haproxy's route
    // and grafana's datasource keep working when the backend moves here. Note thanos keeps
    // /-/ready and /-/healthy at the root regardless -- that is what haproxy checks.
    const std::vector<std::string> query = {
        "ARGS='--endpoint.sd-config-file=" THANOS_ENDPOINTS
        " --query.replica-label=" THANOS_REPLICA_LABEL
        " --grpc-address=0.0.0.0:" THANOS_QUERY_GRPC
        " --http-address=0.0.0.0:" THANOS_QUERY_HTTP
        " --web.route-prefix=/prometheus"
        " --web.external-prefix=/prometheus'\n",
    };
    if (!WriteFile(fsError, THANOS_QUERY_DEF, query)) {
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

    return s_bCubeModified | s_bNetModified | G_MOD(SHARED_ID);
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

    if (enabled) {
        WriteDefaultConf();
        WriteConf(s_ha, sharedId, hostname);

        // seed the target list; non-fatal, and bounded so a wedged etcd
        // cannot hang the commit
        HexUtilSystemF(0, 30, HEX_SDK " lachesis_prometheus_targets");

        // membership changes (node join/remove) do not re-commit this module,
        // so a cron keeps the list current; the generator only rewrites the
        // file when membership actually changed
        WriteLachesisTargetsCronJob();

        log_conf.postRotateCmds = "killall -HUP prometheus";
        WriteLogRotateConf(log_conf);
    }
    else {
        unlink(LACHESIS_TARGETS_CRON);
    }

    if (thanosEnabled)
        WriteThanosConf(s_ctrlAddrs.newValue());

    SystemdCommitService(enabled, NAME);
    // after prometheus: the sidecar exits if it cannot reach it, and while Restart=always
    // covers that, starting in order keeps a boot from logging the failure at all
    SystemdCommitService(thanosEnabled, THANOS_SIDECAR);
    SystemdCommitService(thanosEnabled, THANOS_QUERY);

    return true;
}

CONFIG_MODULE(prometheus, 0, 0, 0, 0, Commit);
CONFIG_REQUIRES(prometheus, cube_scan);

// extra tunings
CONFIG_OBSERVES(prometheus, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(prometheus, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(prometheus, "/var/lib/prometheus");

