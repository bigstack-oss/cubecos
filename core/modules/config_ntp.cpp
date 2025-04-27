// CUBE

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>

#include <cube/systemd_util.h>
#include <cube/cluster.h>

#include "include/role_cubesys.h"

static const char NAME[] = "chronyd";
static const char CONF[] = "/etc/chrony.conf";
const static char SERVER[] = "pool.ntp.org";

static bool s_bCubeModified = false;

static CubeRole_e s_eCubeRole;

// external global variables
CONFIG_GLOBAL_BOOL_REF(IS_MASTER);
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);

// public tunings
CONFIG_TUNING_BOOL(NTP_ENABLED, "ntp.enabled", TUNING_UNPUB, "Set to true to enable ntp service.", true);
CONFIG_TUNING_BOOL(NTP_DEBUG_ENABLED, "ntp.debug.enabled", TUNING_UNPUB, "Set to true to enable ntp debug logs.", false);
CONFIG_TUNING_STR(NTP_SERVER, "ntp.server", TUNING_UNPUB, "Set NTP server.", SERVER, ValidateRegex, DFT_REGEX_STR);

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROLLER);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);

// parse tunings
PARSE_TUNING_BOOL(s_debugEnabled, NTP_DEBUG_ENABLED);
PARSE_TUNING_BOOL(s_enabled, NTP_ENABLED);
PARSE_TUNING_STR(s_server, NTP_SERVER);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_controller, CUBESYS_CONTROLLER, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);

static bool
WriteConf(bool isMaster, const std::string& server,
          const std::string& myip, const std::string& ctrlGrp)
{
    FILE *fout = fopen(CONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s config: %s", NAME, CONF);
        return false;
    }

    fprintf(fout, "server %s iburst\n", server.c_str());
    if (IsControl(s_eCubeRole)) {
        if (!isMaster) {
            std::string masterIp = GetMaster(ctrlGrp);
            fprintf(fout, "server %s iburst\n", masterIp.c_str());
        }

        fprintf(fout, "local stratum 10\n");
        fprintf(fout, "allow all\n");
        fprintf(fout, "rtconutc\n");
        fprintf(fout, "rtcsync\n");
        fprintf(fout, "keyfile /etc/chrony.keys\n");
        fprintf(fout, "makestep 1 -1\n");
    }

    fclose(fout);

    return true;
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

    return modified | s_bCubeModified | G_MOD(IS_MASTER) | G_MOD(MGMT_ADDR);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool isMaster = G(IS_MASTER);
    std::string myIp = G(MGMT_ADDR);
    std::string srv = IsControl(s_eCubeRole) ? s_server : s_controller;
    std::string ctrlGrp = s_ctrlAddrs;

    WriteConf(isMaster, srv, myIp, ctrlGrp);

    SystemdCommitService(s_enabled, NAME);
    if (s_enabled) {
        HexUtilSystemF(0, 0, HEX_SDK " ntp_makestep");
    }

    return true;
}

CONFIG_MODULE(ntp, 0, Parse, 0, 0, Commit);
CONFIG_REQUIRES(ntp, cube_scan);

// extra tunings
CONFIG_OBSERVES(ntp, cubesys, ParseCube, NotifyCube);

CONFIG_SUPPORT_COMMAND("chronyc tracking");
CONFIG_SUPPORT_COMMAND("chronyc sources");

