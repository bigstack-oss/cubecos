// CUBE

#include <hex/log.h>
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

    fprintf(fout, "PROMETHEUS_OPTS='--config.file=" CONF
                  " --storage.tsdb.path=" DATADIR
                  " --storage.tsdb.retention=" TSDB_RP
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
    fprintf(fout, "  - job_name: 'prometheus'\n");
    fprintf(fout, "    static_configs:\n");
    fprintf(fout, "    - targets: ['localhost:9091']\n");
    fprintf(fout, "  - job_name: 'ceph'\n");
    fprintf(fout, "    static_configs:\n");
    if (ha)
        fprintf(fout, "    - targets: ['%s:9285']\n", sharedId.c_str());
    else
        fprintf(fout, "    - targets: ['%s:9283']\n", sharedId.c_str());

    fclose(fout);

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

        log_conf.postRotateCmds = "killall -HUP prometheus";
        WriteLogRotateConf(log_conf);
    }

    SystemdCommitService(enabled, NAME);

    return true;
}

CONFIG_MODULE(prometheus, 0, 0, 0, 0, Commit);
CONFIG_REQUIRES(prometheus, cube_scan);

// extra tunings
CONFIG_OBSERVES(prometheus, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(prometheus, "/var/lib/prometheus");

