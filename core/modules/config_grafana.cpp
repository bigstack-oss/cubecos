// CUBE

#include <hex/log.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <hex/logrotate.h>

#include <cube/systemd_util.h>
#include <cube/cluster.h>

#include "include/role_cubesys.h"

const static char NAME[] = "grafana-server";
const static char CONF[] = "/etc/grafana/grafana.ini";

static CubeRole_e s_eCubeRole;

static bool s_bCubeModified = false;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("grafana", "/var/log/grafana/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);

// parse tunings
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);

static bool
WriteConfig(const std::string& sharedId)
{
    FILE *fout = fopen(CONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s config: %s", NAME, CONF);
        return false;
    }

    fprintf(fout, "[server]\n");
    fprintf(fout, "root_url = http://%s/grafana\n", sharedId.c_str());
    fprintf(fout, "\n");
    fprintf(fout, "[security]\n");
    fprintf(fout, "allow_embedding = true\n");
    fprintf(fout, "\n");
    fprintf(fout, "[users]\n");
    fprintf(fout, "default_theme = light\n");
    fprintf(fout, "\n");
    fprintf(fout, "[auth]\n");
    fprintf(fout, "disable_login_form = true\n");
    fprintf(fout, "\n");
    fprintf(fout, "[auth.anonymous]\n");
    fprintf(fout, "enabled = true\n");
    fprintf(fout, "#org_role = Admin\n");

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

    WriteConfig(sharedId);
    SystemdCommitService(enabled, NAME);

    return true;
}

CONFIG_MODULE(grafana, 0, 0, 0, 0, Commit);

// startup sequence
CONFIG_REQUIRES(grafana, influxdb);

// extra tunings
CONFIG_OBSERVES(grafana, cubesys, ParseCube, NotifyCube);

