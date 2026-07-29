// CUBE SDK

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

static const char NAME[] = "lachesis";
static const char CONF_IN[] = "/etc/cube/lachesis/lachesis.yaml.in";
static const char CONF[] = "/etc/cube/lachesis/lachesis.yaml";

static bool s_bCubeModified = false;

static CubeRole_e s_eCubeRole;

// external global variables
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);

// parse tunings
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);

// rotate daily and enable copytruncate; the unit holds the log open via append:
static LogRotateConf log_conf(NAME, "/var/log/lachesis/*.log", DAILY, 128, 0, true);

static bool
ParseCube(const char* name, const char* value, bool isNew)
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
WriteConf(const std::string& sharedId)
{
    if (HexSystemF(0, "sed -e \"s/@CONTROL_VIP@/%s/\" %s > %s",
                   sharedId.c_str(), CONF_IN, CONF) != 0) {
        HexLogError("failed to update %s", CONF);
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

    return modified | s_bCubeModified | G_MOD(SHARED_ID);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel)) {
        return true;
    }

    // the agent attaches to VM taps, so it belongs wherever instances run
    bool enabled = IsCompute(s_eCubeRole);

    if (enabled) {
        if (!WriteConf(G(SHARED_ID))) {
            return false;
        }

        WriteLogRotateConf(log_conf);
    }

    // no systemctl enable: nothing in cubecos is systemd-enabled, hex_config
    // restarts services on every boot. retry so a settling dep does not fail the commit.
    return SystemdCommitService(enabled, NAME, true);
}

CONFIG_MODULE(lachesis, 0, 0, 0, 0, Commit);
CONFIG_REQUIRES(lachesis, cube_scan);   // SHARED_ID
CONFIG_REQUIRES(lachesis, keystone);    // /etc/admin-openrc.sh
CONFIG_REQUIRES(lachesis, neutron);     // OVN up, so VM taps exist
CONFIG_REQUIRES(lachesis, kafka);       // notification brokers

// extra tunings
CONFIG_OBSERVES(lachesis, cubesys, ParseCube, NotifyCube);

// the WAL carries settled per-tenant byte totals; losing it resets billing counters
CONFIG_MIGRATE(lachesis, "/var/lib/lachesis");
