// CUBE

#include <hex/log.h>
#include <hex/process.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/string_util.h>
#include <hex/process_util.h>
#include <hex/dryrun.h>

#include <cube/cluster.h>

#include "mysql_util.h"
#include "include/role_cubesys.h"

static const char USER[] = "horizon";
static const char DBPASS[] = "ZdDtndK8NmBklLyg";

static const char DJANGO_CONF_IN[] = "/etc/openstack-dashboard/local_settings.in";
static const char DJANGO_CONF[] = "/etc/openstack-dashboard/local_settings";

static bool s_bSetup = true;

static bool s_bCubeModified = false;
static bool s_bTimeModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;

static CubeRole_e s_eCubeRole;

// external global variables
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// private tunings
CONFIG_TUNING_STR(HORIZON_DBPASS, "horizon.db.password", TUNING_UNPUB, "Set horizon db password.", DBPASS, ValidateNone);

// using external tunings
CONFIG_TUNING_SPEC_STR(TIME_TZ);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);

// parse tunings
PARSE_TUNING_STR(s_dbPass, HORIZON_DBPASS);
PARSE_TUNING_X_STR(s_timezone, TIME_TZ, 1);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 2);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 2);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 2);

// should run after mysql services are running.
static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if(!MysqlUtilIsDbExist("horizon")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE horizon") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON horizon.* TO 'horizon'@'localhost' IDENTIFIED BY 'horizon_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON horizon.* TO 'horizon'@'%' IDENTIFIED BY 'horizon_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

static bool
SetupService()
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up horizon");

    HexUtilSystemF(0, 0, "/usr/bin/python3 /usr/share/openstack-dashboard/manage.py migrate --noinput 2>/dev/null");

    return true;
}

static bool
WriteDjangoConf(const char* sharedId, const char* cachesrvs, const char* dbpass, const char* timezone)
{
    if (HexSystemF(0, "sed -e \"s/@SHARED_ID@/%s/\" -e \"s/'@CACHE_SERVERS@'/%s/\" -e \"s/@HORIZON_DB_PASSWORD@/%s/\" "
                      "-e \"s/@DOMAIN@/%s/\" -e \"s/@TIME_ZONE@/%s/\" %s > %s",
                      sharedId, cachesrvs, dbpass, "Default", timezone, DJANGO_CONF_IN, DJANGO_CONF) != 0) {
        HexLogError("failed to update %s", DJANGO_CONF);
        return false;
    }

    return true;
}

static bool
ParseTime(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 1);
    return true;
}

static bool
ParseCube(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 2);
    return true;
}

static void
NotifyTime(bool modified)
{
    s_bTimeModified = s_timezone.modified();
}

static void
NotifyCube(bool modified)
{
    s_bCubeModified = IsModifiedTune(2);
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

    s_bConfigChanged = modified | s_bTimeModified | s_bCubeModified | G_MOD(SHARED_ID);

    return s_bDbPassChanged | s_bConfigChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (!IsControl(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    std::string sharedId = G(SHARED_ID);
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass, s_seed);

    SetupCheck();
    if (!s_bSetup) {
        s_bDbPassChanged = true;
    }

    if (s_bDbPassChanged && IsControl(s_eCubeRole))
        MysqlUtilUpdateDbPass(USER, dbPass.c_str());

    if (s_bConfigChanged) {
        std::string sharedId = G(SHARED_ID);
        std::string cachesrvs = "'" + sharedId + ":11211'";
        std::vector<std::string> tzv = hex_string_util::split(s_timezone.newValue(), '/');
        std::string tz = tzv[0] + "\\/" + tzv[1];
        WriteDjangoConf(sharedId.c_str(), cachesrvs.c_str(), dbPass.c_str(), tz.c_str());
    }

    if (!s_bSetup)
        SetupService();

    return true;
}

CONFIG_MODULE(horizon, 0, Parse, 0, 0, Commit);
CONFIG_REQUIRES(horizon, memcache);

// extra tunings
CONFIG_OBSERVES(horizon, time, ParseTime, NotifyTime);
CONFIG_OBSERVES(horizon, cubesys, ParseCube, NotifyCube);

