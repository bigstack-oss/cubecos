// CUBE

#include <hex/log.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <hex/logrotate.h>

#include <cube/config_file.h>
#include <cube/cluster.h>
#include <cube/systemd_util.h>

#include "mysql_util.h"
#include "include/role_cubesys.h"

static const char OSCMD[] = "/usr/bin/openstack";
static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char USER[] = "skyline";
static const char DBPASS[] = "HXzkHNeeG6ReDojn";
static const char USERPASS[] = "b7qfAoijy1LOZ8Fw";

static const char SKYLINE_CONF_IN[] = "/etc/skyline/skyline.yaml.in";
static const char SKYLINE_CONF[] = "/etc/skyline/skyline.yaml";

// skyline services
static const char API_NAME[] = "skyline-apiserver";

static bool s_bSetup = true;

static bool s_bCubeModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;

static CubeRole_e s_eCubeRole;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("openstack-skyline", "/var/log/skyline/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// private tunings
CONFIG_TUNING_BOOL(SKYLINE_ENABLED, "skyline.enabled", TUNING_UNPUB, "Set to true to enable skyline.", true);
CONFIG_TUNING_STR(SKYLINE_USERPASS, "skyline.user.password", TUNING_UNPUB, "Set skyline user password.", USERPASS, ValidateNone);
CONFIG_TUNING_STR(SKYLINE_DBPASS, "skyline.db.password", TUNING_UNPUB, "Set skyline db password.", DBPASS, ValidateNone);

// public tunigns
CONFIG_TUNING_BOOL(SKYLINE_DEBUG, "skyline.debug.enabled", TUNING_PUB, "Set to true to enable skyline verbose log.", false);

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, SKYLINE_ENABLED);
PARSE_TUNING_BOOL(s_debug, SKYLINE_DEBUG);
PARSE_TUNING_STR(s_userPass, SKYLINE_USERPASS);
PARSE_TUNING_STR(s_dbPass, SKYLINE_DBPASS);

PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 1);

// should run after mysql services are running.
static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if(!MysqlUtilIsDbExist("skyline")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE skyline DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON skyline.* TO 'skyline'@'localhost' IDENTIFIED BY 'skyline_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON skyline.* TO 'skyline'@'%' IDENTIFIED BY 'skyline_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

static bool
SetupService(std::string domain, std::string userPass)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up skyline");

    HexUtilSystemF(0, 0, "cd /usr/local/lib/python3.9/site-packages/skyline_apiserver && /usr/local/bin/alembic -c db/alembic/alembic.ini upgrade head 2>/dev/null");

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the skyline service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s skyline",
                         env.c_str(), OSCMD, domain.c_str(), userPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user skyline admin", env.c_str(), OSCMD);

    return true;
}

static bool
WriteSkylineConf(bool debug, const char* domain, const char* sharedId, const char* userpass, const char* dbpass)
{
    if (HexSystemF(0, "sed -e \"s/@SHARED_ID@/%s/\" -e \"s/@SKYLINE_SERVICE_PASSWORD@/%s/\" -e \"s/@SKYLINE_DB_PASSWORD@/%s/\" "
                      "-e \"s/@DEBUG@/%s/\" -e \"s/@DOMAIN@/%s/\" %s > %s",
                      sharedId, userpass, dbpass, debug ? "true" : "false", domain, SKYLINE_CONF_IN, SKYLINE_CONF) != 0) {
        HexLogError("failed to update %s", SKYLINE_CONF);
        return false;
    }

    return true;
}

static bool
CommitService(bool enabled)
{
    if (IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled, API_NAME, true);       // skyline-apiserver
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
        s_bConfigChanged = true;
        return true;
    }

    s_bDbPassChanged = s_dbPass.modified() | s_bCubeModified;

    s_bConfigChanged = modified | s_bCubeModified;

    return s_bDbPassChanged | s_bConfigChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (!IsControl(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = s_enabled && IsControl(s_eCubeRole);
    std::string myip = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);
    std::string userPass = GetSaltKey(s_saltkey, s_userPass, s_seed);
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass, s_seed);

    SetupCheck();
    if (!s_bSetup) {
        s_bDbPassChanged = true;
    }

    if (s_bDbPassChanged && IsControl(s_eCubeRole))
        MysqlUtilUpdateDbPass(USER, dbPass.c_str());

    if (s_bConfigChanged) {
        WriteSkylineConf(s_debug, s_cubeDomain.c_str(), sharedId.c_str(), userPass.c_str(), dbPass.c_str());
    }

    if (!s_bSetup)
        SetupService(s_cubeDomain, userPass);

    CommitService(enabled);

    WriteLogRotateConf(log_conf);

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_skyline\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    bool enabled = s_enabled && IsControl(s_eCubeRole);
    CommitService(enabled);

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_skyline, RestartMain, RestartUsage);

CONFIG_MODULE(skyline, 0, Parse, 0, 0, Commit);
CONFIG_REQUIRES(skyline, memcache);

// extra tunings
CONFIG_OBSERVES(skyline, cubesys, ParseCube, NotifyCube);
