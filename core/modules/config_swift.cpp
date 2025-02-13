// CUBE

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>

#include <cube/cluster.h>

#include "include/role_cubesys.h"

static const char SETUP_MARK[] = "/etc/appliance/state/swift_done";
static const char SETUP_S3_MARK[] = "/etc/appliance/state/s3_done";

static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char OSCMD[] = "/usr/bin/openstack";

static ConfigString s_hostname;

static bool s_bSetup = true;
static bool s_bSetupS3 = true;

static bool s_bCubeModified = false;

static bool s_bEndpointChanged = false;
static bool s_bS3EndpointChanged = false;

static CubeRole_e s_eCubeRole;

// external global variables
CONFIG_GLOBAL_BOOL_REF(IS_MASTER);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(SWIFT_ENABLED, "swift.enabled", TUNING_UNPUB, "Set to true to enable swift.", true);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_REGION);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, SWIFT_ENABLED);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);

static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    struct stat ms;

    if(stat(SETUP_MARK, &ms) != 0) {
        // primary control node has setup swift, secondary control node can skip
        if (s_ha && !G(IS_MASTER))
            HexSystemF(0, "touch %s", SETUP_MARK);
        else
            s_bSetup = false;
    }

    return false;
}

static bool
SetupS3Check()
{
    if (!IsControl(s_eCubeRole))
        return true;

    struct stat ms;

    if(stat(SETUP_S3_MARK, &ms) != 0) {
        // primary control node has setup swift, secondary control node can skip
        if (s_ha && !G(IS_MASTER))
            HexSystemF(0, "touch %s", SETUP_S3_MARK);
        else
            s_bSetupS3 = false;
    }

    return false;
}

// Setup should run after keystone.
static bool
SetupSwift(void)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up swift");

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the service entity
    HexUtilSystemF(0, 0, "%s %s service create --name swift "
                         "--description \"Openstack Object Storage\" object-store",
                         env.c_str(), OSCMD);

    HexSystemF(0, "touch %s", SETUP_MARK);

    return true;
}

static bool
SetupS3(void)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up s3");

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the service entity
    HexUtilSystemF(0, 0, "%s %s service create --name s3 "
                         "--description \"Simple Storage Service\" s3",
                         env.c_str(), OSCMD);

    HexSystemF(0, "touch %s", SETUP_S3_MARK);

    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating swift endpoint");

    std::string pub = "http://" + external + ":8888/swift/v1/%\\(project_id\\)s";
    std::string adm = "http://" + endpoint + ":8888/swift/v1/%\\(project_id\\)s";
    std::string intr = "http://" + endpoint + ":8888/swift/v1/%\\(project_id\\)s";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "object-store", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static bool
UpdateS3Endpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating s3 endpoint");

    std::string pub = "http://" + external + ":8888";
    std::string adm = "http://" + endpoint + ":8888";
    std::string intr = "http://" + endpoint + ":8888";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "s3", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

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
Parse(const char *name, const char *value, bool isNew)
{
    bool r = true;

    TuneStatus s = ParseTune(name, value, isNew);
    if (s == TUNE_INVALID_NAME) {
        HexLogWarning("Unknown settings name \"%s\" = \"%s\" ignored", name, value);
    }
    else if (s == TUNE_INVALID_VALUE) {
        HexLogError("Invalid settings value \"%s\" = \"%s\"", name, value);
        r = false;
    }
    return r;
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        return true;
    }

    s_bEndpointChanged = s_bCubeModified | G_MOD(SHARED_ID) | G_MOD(EXTERNAL);
    s_bS3EndpointChanged = s_bCubeModified | G_MOD(SHARED_ID) | G_MOD(EXTERNAL);

    return modified | s_bEndpointChanged | s_bS3EndpointChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    SetupCheck();
    if (!s_bSetup) {
        s_bEndpointChanged = true;
        SetupSwift();
    }

    SetupS3Check();
    if (!s_bSetupS3) {
        s_bS3EndpointChanged = true;
        SetupS3();
    }

    if (s_bEndpointChanged)
        UpdateEndpoint(sharedId, external, s_cubeRegion.newValue());

    if (s_bS3EndpointChanged)
        UpdateS3Endpoint(sharedId, external, s_cubeRegion.newValue());

    return true;
}

CONFIG_MODULE(swift, 0, Parse, 0, 0, Commit);
// startup sequence
CONFIG_REQUIRES(swift, memcache);

// extra tunings
CONFIG_OBSERVES(swift, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(swift, SETUP_MARK);
CONFIG_MIGRATE(swift, SETUP_S3_MARK);

