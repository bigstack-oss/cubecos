// CUBE

#include <hex/log.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/dryrun.h>
#include <hex/logrotate.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <cube/systemd_util.h>
#include <cube/cluster.h>

#include "include/role_cubesys.h"

const static char NAME[] = "opensearch-dashboards";
const static char CONF[] = "/etc/opensearch-dashboards/opensearch_dashboards.yml";

static CubeRole_e s_eCubeRole;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("opensearch-dashboards", "/var/log/opensearch-dashboards/*.log", DAILY, 128, 0, true);

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);

// parse tunings
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);

static bool
WriteConfig()
{
    FILE *fout = fopen(CONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s config: %s", NAME, CONF);
        return false;
    }

    fprintf(fout, "server.host: \"::\"\n");
    fprintf(fout, "server.port: \"5601\"\n");
    fprintf(fout, "server.basePath: \"/opensearch-dashboards\"\n");
    fprintf(fout, "server.rewriteBasePath: true\n");
    fprintf(fout, "logging.dest: /var/log/opensearch-dashboards/opensearch-dashboards.log\n");
    fprintf(fout, "opensearch.hosts: [http://127.0.0.1:9200]\n");
    fprintf(fout, "opensearch.ssl.verificationMode: none\n");
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
    s_eCubeRole = GetCubeRole(s_cubeRole);
}

static bool
Commit(bool modified, int dryLevel)
{
    if (!s_cubeRole.modified())
        return true;

    // TODO: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || IsEdge(s_eCubeRole))
        return true;

    bool enabled = IsControl(s_eCubeRole);
    if (enabled)
        HexUtilSystemF(0, 0, HEX_SDK " opensearch_ops_reqid_search");

    WriteConfig();
    SystemdCommitService(enabled, NAME);

    WriteLogRotateConf(log_conf);

    return true;
}

static int
ClusterReadyMain(int argc, char **argv)
{
    bool enabled = IsControl(s_eCubeRole);

    if (enabled)
        HexUtilSystemF(0, 0, HEX_SDK " opensearch_ops_reqid_search");

    return EXIT_SUCCESS;
}

CONFIG_MODULE(opensearch-dashboards, 0, 0, 0, 0, Commit);

// startup sequence
CONFIG_REQUIRES(opensearch-dashboards, opensearch);

// extra tunings
CONFIG_OBSERVES(opensearch-dashboards, cubesys, ParseCube, NotifyCube);

CONFIG_TRIGGER_WITH_SETTINGS(opensearch-dashboards, "cluster_ready", ClusterReadyMain);

