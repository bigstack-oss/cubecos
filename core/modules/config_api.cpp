// CUBE

#include <unistd.h>
#include <hex/log.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_global.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/dryrun.h>
#include <hex/logrotate.h>

#include <cube/systemd_util.h>

#include "include/role_cubesys.h"

#define MARKER_API_IDP "/etc/appliance/state/api_idp_done"

static const char API_NAME[] = "cube-cos-api";

static bool s_bCubeModified = false;

static CubeRole_e s_eCubeRole;

// use external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);

// parse tunings
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);

// external global variables
// we still need to listen to changes on MGMT_ADDR to restart cube-cos-api
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// rotate daily and enable copytruncate
static LogRotateConf log_conf(API_NAME, "/var/log/cube-cos-api/*.log", DAILY, 128, 0, true);

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

    return modified | s_bCubeModified | G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel)) {
        return true;
    }

    std::string sharedId = G(SHARED_ID);
    if (access(MARKER_API_IDP, F_OK) != 0) {
        HexUtilSystemF(0, 0, HEX_SDK " api_idp_config %s", sharedId.c_str());
        HexSystemF(0, "touch %s", MARKER_API_IDP);
    }

    // start cube-cos-api
    return SystemdCommitService(true, API_NAME, true);
}

CONFIG_MODULE(api, 0, 0, 0, 0, Commit);
CONFIG_REQUIRES(api, cube_scan);
CONFIG_REQUIRES(api, mongodb);
CONFIG_REQUIRES(api, keycloak);
CONFIG_REQUIRES(api, influxdb);
CONFIG_REQUIRES(api, cyborg);
CONFIG_REQUIRES(api, apache2);

// extra tunings
CONFIG_OBSERVES(api, cubesys, ParseCube, NotifyCube);
