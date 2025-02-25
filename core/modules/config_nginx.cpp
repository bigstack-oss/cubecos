// CUBE

#include <hex/log.h>
#include <hex/process.h>

#include <hex/config_global.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/dryrun.h>

#include <cube/systemd_util.h>

#include "include/role_cubesys.h"

static const char NGINX_NAME[] = "nginx";
static const char NGINX_CONF_IN[] = "/etc/nginx/nginx.conf.in";
static const char NGINX_CONF[] = "/etc/nginx/nginx.conf";

static bool s_bCubeModified = false;

static bool s_bConfigChanged = false;

static CubeRole_e s_eCubeRole;

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);

// parse tunings
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);

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
WriteNginxConf(const char* myip, const char* sharedId)
{
    if (HexSystemF(0, "sed -e \"s/@MGMT_ADDR@/%s/\" -e \"s/@SHARED_ID@/%s/\" %s > %s", myip, sharedId, NGINX_CONF_IN, NGINX_CONF) != 0) {
        HexLogError("failed to update %s", NGINX_CONF);
        return false;
    }

    return true;
}

static bool
CommitService(bool enabled)
{
    if (IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled, NGINX_NAME, true);     // nginx
    }

    return true;
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        s_bConfigChanged = true;
        return true;
    }

    s_bConfigChanged = modified | s_bCubeModified | G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID);

    return s_bConfigChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (!IsControl(s_eCubeRole) || !CommitCheck(modified, dryLevel)) {
        return true;
    }

    bool enabled = IsControl(s_eCubeRole);
    std::string myip = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);

    if (s_bConfigChanged) {
        WriteNginxConf(myip.c_str(), sharedId.c_str());
    }

    CommitService(enabled);

    return true;
}

CONFIG_MODULE(nginx, 0, 0, 0, 0, Commit);
CONFIG_REQUIRES(nginx, skyline);

// extra tunings
CONFIG_OBSERVES(skyline, cubesys, ParseCube, NotifyCube);
