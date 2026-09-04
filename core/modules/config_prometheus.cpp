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

static CubeRole_e s_eCubeRole;

static bool s_bCubeModified = false;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("prometheus", "/var/log/prometheus/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);

// parse tunings
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
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
WriteConf(bool ha, const std::string& sharedId)
{
    FILE *fout = fopen(CONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s conf file: %s", NAME, CONF);
        return false;
    }

    fprintf(fout, "global:\n");
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
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        return true;
    }

    return s_bCubeModified | G_MOD(SHARED_ID);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = IsControl(s_eCubeRole);
    std::string sharedId = G(SHARED_ID);

    if (enabled) {
        WriteDefaultConf();
        WriteConf(s_ha, sharedId);

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

    SystemdCommitService(enabled, NAME);

    return true;
}

CONFIG_MODULE(prometheus, 0, 0, 0, 0, Commit);
CONFIG_REQUIRES(prometheus, cube_scan);

// extra tunings
CONFIG_OBSERVES(prometheus, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(prometheus, "/var/lib/prometheus");

