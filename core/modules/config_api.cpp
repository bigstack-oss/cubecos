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
#include <cube/cluster.h>

#include "include/role_cubesys.h"

#define MARKER_API_IDP "/etc/appliance/state/api_idp_done"

static const char API_NAME[] = "cube-cos-api";
static const char API_CONF_IN[] = "/etc/cube/api/cube-cos-api.yaml.in";
static const char API_CONF[] = "/etc/cube/api/cube-cos-api.yaml";

static bool s_bCubeModified = false;
static bool s_bMongodbModified = false;

static CubeRole_e s_eCubeRole;

// use external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_STR(MONGODB_DBPASS);

// parse tunings
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 1);
PARSE_TUNING_X_STR(s_dbPass, MONGODB_DBPASS, 2);

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
ParseMongodb(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 2);
    return true;
}

static void
NotifyMongodb(bool modified)
{
    s_bMongodbModified = IsModifiedTune(2);
}

static bool
WriteApiConf(std::string mongodbPass)
{
    if (HexSystemF(0, "sed -e \"s/@MONGODB_ADMIN_ACCESS@/%s/\" %s > %s", mongodbPass.c_str(), API_CONF_IN, API_CONF) != 0) {
        HexLogError("failed to update %s", API_CONF);
        return false;
    }

    return true;
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        return true;
    }

    return modified | s_bCubeModified | s_bMongodbModified | G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID);
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

    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());
    if (!WriteApiConf(dbPass.c_str())) {
        return false;
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
CONFIG_OBSERVES(api, mongodb, ParseMongodb, NotifyMongodb);
