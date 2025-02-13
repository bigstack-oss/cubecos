// CUBE

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/process.h>
#include <hex/filesystem.h>
#include <hex/process_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>

#include <cube/systemd_util.h>
#include <cube/cluster.h>

#include "include/role_cubesys.h"

typedef std::pair<std::string, std::string> Setting;
typedef std::vector<Setting> SettingList;

static SettingList s_defSettings;

const static char USER[] = "memcache";
const static char GROUP[] = "memcache";
static const char NAME[] = "memcached";
static const char ENV[] = "/etc/sysconfig/memcached";

static bool s_bCubeModified = false;

static CubeRole_e s_eCubeRole;

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);

// public tunings
CONFIG_TUNING_BOOL(MEMCACHE_DEBUG_ENABLED, "memcache.debug.enabled", TUNING_UNPUB, "Set to true to enable memcache debug logs.", false);

// private tunings
CONFIG_TUNING_BOOL(MEMCACHE_ENABLED, "memcache.enabled", TUNING_UNPUB, "Set to true to enable memcache service.", true);

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);

// parse tunings
PARSE_TUNING_BOOL(s_debugEnabled, MEMCACHE_DEBUG_ENABLED);
PARSE_TUNING_BOOL(s_enabled, MEMCACHE_ENABLED);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);

static void
UpdateConfig(std::string ctrlIp)
{
    if (!IsControl(s_eCubeRole))
        return;

    FILE *fout = fopen(ENV, "w");
    if (!fout) {
        HexLogFatal("Unable to write memcached config: %s", ENV);
        return;
    }

    fprintf(fout, "PORT=\"11211\"\n");
    fprintf(fout, "USER=\"memcached\"\n");
    fprintf(fout, "MAXCONN=\"32768\"\n");
    fprintf(fout, "CACHESIZE=\"64\"\n");
    fprintf(fout, "OPTIONS=\"-l %s\"\n", ctrlIp.c_str());

    fclose(fout);
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

    return modified | s_bCubeModified | G_MOD(MGMT_ADDR);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = s_enabled && IsControl(s_eCubeRole);
    std::string myip = G(MGMT_ADDR);

    UpdateConfig(myip);

    SystemdCommitService(enabled, NAME);

    return true;
}

CONFIG_MODULE(memcache, 0, Parse, 0, 0, Commit);
// keystone may alter API endpoints and require to refresh memcache content
CONFIG_REQUIRES(memcache, keystone);

// extra tunings
CONFIG_OBSERVES(memcache, cubesys, ParseCube, NotifyCube);

CONFIG_SUPPORT_COMMAND(HEX_SDK " memcache_stats");

