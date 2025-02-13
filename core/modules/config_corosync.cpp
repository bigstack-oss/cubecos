// CUBE

#include <unistd.h>

#include <hex/log.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/string_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>

#include <cube/network.h>
#include <cube/cluster.h>
#include <cube/systemd_util.h>

#include "include/role_cubesys.h"

const static char NAME[] = "corosync";
const static char CONF[] = "/etc/corosync/corosync.conf";
const static char CLUSTER_KEY[] = "control";

static bool s_bCubeModified = false;
static CubeRole_e s_eCubeRole;

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(MGMT_CIDR);
CONFIG_GLOBAL_STR_REF(STORAGE_F_CIDR);

// private tunings
CONFIG_TUNING_BOOL(COROSYNC_ENABLED, "corosync.enabled", TUNING_UNPUB, "Set to true to enable corosync.", true);
CONFIG_TUNING_STR(COROSYNC_CLUSTER_KEY, "corosync.cluster.key", TUNING_UNPUB, "Set corosync cluster key.", CLUSTER_KEY, ValidateNone);

// external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, COROSYNC_ENABLED);
PARSE_TUNING_STR(s_clusterKey, COROSYNC_CLUSTER_KEY);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);

static bool
WriteConfig(const std::string &clusterName, const std::string &mgmtNetwork,
            const std::string &storNetwork, const std::string &ctrlAddrs)
{
    FILE *fout = fopen(CONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s config: %s", NAME, CONF);
        return false;
    }

    fprintf(fout, "totem {\n");
    fprintf(fout, "    version: 2\n");
    fprintf(fout, "    cluster_name: cube-%s\n", clusterName.c_str());
    fprintf(fout, "    token: 10000\n");
    fprintf(fout, "    token_retransmits_before_loss_const: 10\n");
    fprintf(fout, "    clear_node_high_bit: yes\n");
    fprintf(fout, "    crypto_cipher: none\n");
    fprintf(fout, "    crypto_hash: none\n");
    fprintf(fout, "    interface {\n");
    fprintf(fout, "        ringnumber: 0\n");
    fprintf(fout, "        bindnetaddr: %s\n", mgmtNetwork.c_str());
    fprintf(fout, "        mcastport: 5405\n");
    fprintf(fout, "        ttl: 1\n");
    fprintf(fout, "    }\n");

    if (mgmtNetwork != storNetwork) {
        fprintf(fout, "    interface {\n");
        fprintf(fout, "        ringnumber: 1\n");
        fprintf(fout, "        bindnetaddr: %s\n", storNetwork.c_str());
        fprintf(fout, "        mcastport: 5407\n");
        fprintf(fout, "        ttl: 1\n");
        fprintf(fout, "    }\n");
    }

    fprintf(fout, "}\n");
    fprintf(fout, "\n");

    fprintf(fout, "nodelist {\n");
    auto addrs = hex_string_util::split(ctrlAddrs, ',');
    for (auto addr : addrs) {
        std::string octet4 = hex_string_util::split(addr, '.')[3];
        fprintf(fout, "    node {\n");
        fprintf(fout, "        nodeid: %s\n", octet4.c_str());
        fprintf(fout, "        ring0_addr: %s\n", addr.c_str());
        fprintf(fout, "    }\n");
    }
    fprintf(fout, "}\n");
    fprintf(fout, "\n");

    fprintf(fout, "logging {\n");
    fprintf(fout, "    fileline: off\n");
    fprintf(fout, "    to_stderr: no\n");
    fprintf(fout, "    to_logfile: no\n");
    fprintf(fout, "    to_syslog: yes\n");
    fprintf(fout, "    syslog_facility: daemon\n");
    fprintf(fout, "    debug: off\n");
    fprintf(fout, "    timestamp: on\n");
    fprintf(fout, "    logger_subsys {\n");
    fprintf(fout, "        subsys: QUORUM\n");
    fprintf(fout, "        debug: off\n");
    fprintf(fout, "    }\n");
    fprintf(fout, "}\n");
    fprintf(fout, "\n");

    fprintf(fout, "quorum {\n");
    fprintf(fout, "    provider: corosync_votequorum\n");
    fprintf(fout, "    expected_votes: 1\n");
    fprintf(fout, "    wait_for_all: 1\n");
    fprintf(fout, "    last_man_standing: 1\n");
    fprintf(fout, "    last_man_standing_window: 10000\n");
    fprintf(fout, "    auto_tie_breaker: 1\n");
    fprintf(fout, "    auto_tie_breaker_node: lowest\n");
    fprintf(fout, "}\n");
    fprintf(fout, "\n");

    fclose(fout);

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

    return modified | s_bCubeModified | G_MOD(MGMT_ADDR) | G_MOD(MGMT_CIDR) | G_MOD(STORAGE_F_CIDR);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (!IsControl(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = s_enabled && IsControl(s_eCubeRole);

    std::string clusterName = GetSaltKey(s_saltkey, s_clusterKey, s_seed);
    std::string mgmtNetwork = hex_string_util::split(G(MGMT_CIDR).c_str(), '/')[0];
    std::string storNetwork = hex_string_util::split(G(STORAGE_F_CIDR).c_str(), '/')[0];
    std::string ctrlAddrs = s_ha ? s_ctrlAddrs : G(MGMT_ADDR);

    if (enabled)
        WriteConfig(clusterName, mgmtNetwork, storNetwork, ctrlAddrs);

    SystemdCommitService(enabled, NAME);

    return true;
}

CONFIG_MODULE(corosync, 0, Parse, 0, 0, Commit);

// startup sequence
CONFIG_REQUIRES(corosync, cube_scan);

// extra tunings
CONFIG_OBSERVES(corosync, cubesys, ParseCube, NotifyCube);

CONFIG_SUPPORT_COMMAND("corosync-cmapctl | grep members");

