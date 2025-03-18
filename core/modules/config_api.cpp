// CUBE

#include <unistd.h>
#include <hex/log.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_global.h>
#include <hex/config_module.h>
#include <hex/dryrun.h>
#include <hex/logrotate.h>

#include <cube/systemd_util.h>

#define MARKER_API_IDP "/etc/appliance/state/api_idp_done"

static const char API_NAME[] = "cube-cos-api";

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// rotate daily and enable copytruncate
static LogRotateConf log_conf(API_NAME, "/var/log/cube-cos-api/*.log", DAILY, 128, 0, true);

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        return true;
    }

    return modified | G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (!CommitCheck(modified, dryLevel)) {
        return true;
    }

    std::string sharedId = G(SHARED_ID);
    if (access(MARKER_API_IDP, F_OK) != 0) {
        HexUtilSystemF(0, 0, HEX_SDK " api_idp_config %s", sharedId.c_str());
        HexSystemF(0, "touch %s", MARKER_API_IDP);
    }

    // enable cube-cos-api
    if (HexUtilSystemF(0, 0, "systemctl enable %s", API_NAME) != 0) {
        HexLogError("failed to start %s service", API_NAME);
        return false;
    }

    // start cube-cos-api
    return SystemdCommitService(true, API_NAME, true);
}

CONFIG_MODULE(api, 0, 0, 0, 0, Commit);
CONFIG_REQUIRES(api, cube_scan);
CONFIG_REQUIRES(api, keycloak);
