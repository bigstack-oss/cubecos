// CUBE

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include <hex/log.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/string_util.h>
#include <hex/logrotate.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>

#include <cube/cluster.h>
#include <cube/network.h>
#include <cube/systemd_util.h>

#include "include/role_cubesys.h"

const static char NAME[] = "pacemaker";
const static char PCSD[] = "pcsd";
const static char FORCE_NEW_MARK[] = "/etc/appliance/state/pacemaker_new_setup";

static CubeRole_e s_eCubeRole;

static ConfigString s_hostname;

static bool s_bCubeModified = false;
static bool s_bNetModified = false;

static bool s_bRcsChanged = false;

static const char IPMI_DETECT[] = "/etc/appliance/state/ipmi_detected";

static const char AUTH_KEY[] = "/etc/pacemaker/authkey";

static LogRotateConf log_conf("pacemaker", "/var/log/pacemaker/pacemaker.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_BOOL_REF(IS_MASTER);
CONFIG_GLOBAL_STR_REF(CTRL_IP);
CONFIG_GLOBAL_STR_REF(MGMT_IF);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);

// private tunings
CONFIG_TUNING_BOOL(PACEMAKER_ENABLED, "pacemaker.enabled", TUNING_UNPUB, "Set to true to enable corosync.", true);

// external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_HOSTS);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, PACEMAKER_ENABLED);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_ctrlHosts, CUBESYS_CONTROL_HOSTS, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);

static bool
SetupCluster(const bool enabled, const bool ha, std::string sharedId, const std::string& ctrlHosts)
{
    if (!enabled)
        return true;

    HexUtilSystemF(0, 0, "pcs property set pe-warn-series-max=\"1000\" "
                         "pe-error-series-max=\"1000\" cluster-recheck-interval=\"5min\"");

    HexUtilSystemF(0, 0, "pcs property set stonith-enabled=false");

    if (ha) {
        auto hosts = hex_string_util::split(ctrlHosts, ',');

        HexUtilSystemF(0, 0, "pcs resource create vip ocf:heartbeat:IPaddr2 "
                             "ip=\"%s\" op monitor interval=\"30s\"", sharedId.c_str());
        HexUtilSystemF(0, 0, "pcs resource create vaw systemd:vaw op monitor interval=\"30s\"");
        HexUtilSystemF(0, 0, "pcs constraint colocation add vip with vaw score=INFINITY");
        HexUtilSystemF(0, 0, "pcs constraint order vip then vaw");
        HexUtilSystemF(0, 0, "pcs resource create haproxy systemd:haproxy-ha op monitor interval=\"1s\"");
        HexUtilSystemF(0, 0, "pcs constraint colocation add vip with haproxy score=INFINITY");
        HexUtilSystemF(0, 0, "pcs constraint order vip then haproxy");
        HexUtilSystemF(0, 0, "pcs resource create cinder-volume systemd:openstack-cinder-volume");

        HexUtilSystemF(0, 0, "pcs resource create ovndb_servers ocf:ovn:ovndb-servers "
                             "manage_northd=yes master_ip=%s listen_on_master_ip_only=no promotable", sharedId.c_str());
        HexUtilSystemF(0, 0, "pcs resource meta ovndb_servers-clone notify=true clone-max=%lu", hosts.size());
        HexUtilSystemF(0, 0, "pcs constraint order start vip then promote ovndb_servers-clone");
        HexUtilSystemF(0, 0, "pcs constraint colocation add vip with master ovndb_servers-clone");

        for (auto host : hosts) {
            HexUtilSystemF(0, 0, "pcs constraint location vip prefers %s --force", host.c_str());
            HexUtilSystemF(0, 0, "pcs constraint location haproxy prefers %s --force", host.c_str());
            HexUtilSystemF(0, 0, "pcs constraint location cinder-volume prefers %s --force", host.c_str());
            HexUtilSystemF(0, 0, "pcs constraint location ovndb_servers-clone prefers %s --force", host.c_str());
        }

        if (hosts.size() <= 2)
            HexUtilSystemF(0, 0, "pcs property set no-quorum-policy=\"ignore\"");
    }

    return true;
}

static bool
ParseCube(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 1);
    return true;
}

static bool
ParseNet(const char *name, const char *value, bool isNew)
{
    if (strcmp(name, NET_HOSTNAME) == 0) {
        s_hostname.parse(value, isNew);
    }

    return true;
}

static void
NotifyCube(bool modified)
{
    s_bCubeModified = IsModifiedTune(1);
    s_eCubeRole = GetCubeRole(s_cubeRole);
}

static void
NotifyNet(bool modified)
{
    s_bNetModified = s_hostname.modified();
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

    s_bRcsChanged = s_bCubeModified | s_bNetModified | G_MOD(IS_MASTER) | G_MOD(MGMT_IF) | G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID);

    return modified | s_bRcsChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (!(IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = s_enabled && IsControl(s_eCubeRole);
    bool isMaster = s_ha && G(IS_MASTER);
    bool isMasterRejoin = (G(IS_MASTER) && access(CONTROL_REJOIN, F_OK) == 0) ? true : false;
    std::string mgmtIf = G(MGMT_IF);
    std::string myIp = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);

    if (G(IS_MASTER) && access(AUTH_KEY, F_OK) != 0) {
        HexLogInfo("create pacemaker auth key");
        HexSystemF(0, "dd if=/dev/urandom of=%s bs=4096 count=1 2>/dev/null", AUTH_KEY);
    }
    else if ((!G(IS_MASTER) && IsControl(s_eCubeRole)) || isMasterRejoin) {
        std::string peer = GetControllerPeers(myIp, s_ctrlAddrs)[0];
        HexUtilSystemF(0, 0, "rsync root@%s:%s %s 2>/dev/null", peer.c_str(), AUTH_KEY, AUTH_KEY);
    }

    isMaster = isMaster & !isMasterRejoin;

    if (enabled) {
        if (isMaster) {
            HexUtilSystemF(0, 0, "ip addr add %s dev %s label %s",
                                 sharedId.c_str(), mgmtIf.c_str(), mgmtIf.c_str());
        }
        else {
            SystemdCommitService(enabled, NAME);
            SystemdCommitService(enabled, PCSD);
        }
    }

    if (IsCompute(s_eCubeRole)) {
        SystemdCommitService(s_enabled, PCSD);
        if (!IsConverged(s_eCubeRole) && !IsCore(s_eCubeRole)) {
            HexUtilSystemF(0, 0, HEX_SDK " pacemaker_remote_cleanup");
        }
    }

    WriteLogRotateConf(log_conf);

    // vip could be misssing when corosync doesn't form quorum between system reboots
    HexUtilSystemF(0, 0, HEX_SDK " health_vip_check || " HEX_SDK " health_vip_repair");

    return true;
}

static bool
CommitLast(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (!(IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = s_enabled && IsControl(s_eCubeRole);
    bool isMasterRejoin = (G(IS_MASTER) && access(CONTROL_REJOIN, F_OK) == 0) ? true : false;
    bool isMaster = s_ha && G(IS_MASTER);
    std::string mgmtIf = G(MGMT_IF);
    // parent IF could be changed because additional linux bridge created by neutron
    std::string pIf = GetParentIf(mgmtIf);
    std::string sharedId = G(SHARED_ID);

    isMaster = isMaster & !isMasterRejoin;

    if (enabled) {
        if (isMaster) {
            HexUtilSystemF(0, 0, "ip addr del %s/32 dev %s label %s",
                                 sharedId.c_str(), pIf.c_str(), pIf.c_str());
            SystemdCommitService(enabled, NAME);
            SystemdCommitService(enabled, PCSD);
        }

        // is master or the only controller
        if (s_bRcsChanged || access(FORCE_NEW_MARK, F_OK) == 0 || access(CUBE_MIGRATE, F_OK) == 0) {
            if (isMaster || (IsControl(s_eCubeRole) && !s_ha)) {
                HexUtilSystemF(0, 0, HEX_SDK " wait_for_pacemaker 30");
                SetupCluster(enabled, s_ha, sharedId, s_ctrlHosts);
            }
            else if (IsModerator(s_eCubeRole)) {
                HexUtilSystemF(0, 0, "pcs constraint remove location-vip-%s-INFINITY", s_hostname.c_str());
            }
            unlink(FORCE_NEW_MARK);
        }
    }

    // pure compute node
    if (IsCompute(s_eCubeRole) && !IsConverged(s_eCubeRole) && !IsCore(s_eCubeRole)) {
        std::string ctrlIp = G(CTRL_IP);
        std::string master = GetMaster(s_ha, ctrlIp, s_ctrlAddrs);
        HexUtilSystemF(0, 0, HEX_SDK " migrate_pacemaker_remote %s", master.c_str());
    }

    return true;
}

static void
StatusUsage(void)
{
    fprintf(stderr, "Usage: %s status_pacemaker\n", HexLogProgramName());
}

static int
StatusMain(int argc, char* argv[])
{
    if (argc != 1) {
        StatusUsage();
        return EXIT_FAILURE;
    }

    HexSpawn(0, "/usr/sbin/pcs", "status", NULL);

    return EXIT_SUCCESS;
}

static int
ClusterUpdateMain(int argc, char **argv)
{
    if (argc != 5)  /* argv[1]: add/remove, argv[2]: hostname, argv[3]: mgmtip, argv[4]: role  */
        return EXIT_FAILURE;

    std::string action = argv[1];
    std::string hostname = argv[2];
    std::string mgmtip = argv[3];
    std::string role = argv[4];

    if (IsControl(s_eCubeRole)) {
        if (action == "add" && role == "compute") {
            HexLogInfo("add %s host %s@%s to pacemaker cluster", role.c_str(), hostname.c_str(), mgmtip.c_str());
            HexUtilSystemF(0, 0, HEX_SDK " pacemaker_remote_add %s", hostname.c_str());
        }
        else if (action == "remove" && role == "compute") {
            HexLogInfo("remove %s host %s@%s from pacemaker cluster", role.c_str(), hostname.c_str(), mgmtip.c_str());
            HexUtilSystemF(0, 0, HEX_SDK " pacemaker_remote_remove %s", hostname.c_str());
        }
    }

    return EXIT_SUCCESS;
}

CONFIG_COMMAND(status_pacemaker, StatusMain, StatusUsage);

CONFIG_MODULE(pacemaker, 0, Parse, 0, 0, Commit);
CONFIG_MODULE(pacemaker_last, 0, 0, 0, 0, CommitLast);
CONFIG_REQUIRES(pacemaker, corosync);
CONFIG_LAST(pacemaker_last);

// extra tunings
CONFIG_OBSERVES(pacemaker, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(pacemaker, cubesys, ParseCube, NotifyCube);

CONFIG_TRIGGER_WITH_SETTINGS(pacemaker, "cluster_map_update", ClusterUpdateMain);

