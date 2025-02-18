#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include <hex/log.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/filesystem.h>
#include <hex/string_util.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <hex/logrotate.h>

#include <cube/systemd_util.h>
#include <cube/config_file.h>
#include <cube/cluster.h>

#include "include/role_cubesys.h"

const static char SERVICE[] = "mongodb";
const static char DATA_DIR[] = "/var/lib/mongo";

static const char USER[] = "mongod";
static const char GROUP[] = "mongod";

static bool s_bCubeModified = false;
static bool s_bNetModified = false;

static ConfigString s_hostname;
static CubeRole_e s_eCubeRole;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("mongodb", "/var/log/mongodb/*.log", DAILY, 128, 0, true);

// private tunings
CONFIG_TUNING_BOOL(MONGODB_ENABLED, "mongodb.enabled", TUNING_UNPUB, "Set to true to enable mongodb.", true);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_HOSTS);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, MONGODB_ENABLED);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_ctrlHosts, CUBESYS_CONTROL_HOSTS, 1);

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
ShouldCommit(bool modified)
{
    if (IsBootstrap()) {
        return true;
    }

    return modified | s_bCubeModified | s_bNetModified;
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
NotifyNet(bool modified)
{
    s_bNetModified = s_hostname.modified();
}

static void
NotifyCube(bool modified)
{
    s_bCubeModified = IsModifiedTune(1);
    s_eCubeRole = GetCubeRole(s_cubeRole);
}

static int
CheckAndInitAdminUser()
{
    int result = HexUtilSystemF(FWD, 0, "mongosh --quiet --eval 'db.getSiblingDB(\"admin\").getUser(\"admin\")' | grep admin");
    if (result == 0) {
        HexLogInfo("admin user is already created, skip creating");
        return 0;
    }

    result = HexUtilSystemF(FWD, 0, "mongosh --quiet --eval 'db.getSiblingDB(\"admin\").createUser({user:\"admin\",pwd:\"admin\",roles:[{role:\"userAdminAnyDatabase\",db:\"admin\"}]})'");
    if (result != 0) {
        HexLogError("failed to create admin user");
        return result;
    }

    return 0;
}

static bool
IsHostRegistered(char* host)
{
    int result = HexUtilSystemF(FWD, 0, "mongosh --quiet --eval 'rs.conf().members' | grep %s", host);
    if (result == 0) {
        return true;
    }

    return false;
}

static void
AppendCtrlPeerHostsIfObserved(std::vector<std::string>& ctrlHosts)
{
    std::vector<std::string> peerCtrlHosts = GetControllerPeers(s_hostname, s_ctrlHosts);
    for (auto peerCtrlHost : peerCtrlHosts) {
        ctrlHosts.push_back(peerCtrlHost);
        HexLogInfo("peer controller %s is observed, going to be registered", peerCtrlHost.c_str());
    }
}

static int
SyncHostsToReplicaSet(std::vector<std::string>& ctrlHosts)
{
    for (auto ctrlHost : ctrlHosts) {
        if (IsHostRegistered(const_cast<char*>(ctrlHost.c_str()))) {
            HexLogInfo("%s is already added in replicaSet, skip adding", ctrlHost.c_str());
            continue;
        }

        int result = HexUtilSystemF(FWD, 0, "mongosh --quiet --eval 'rs.add(\"%s\")'", ctrlHost.c_str());
        if (result != 0) {
            HexLogError("failed to add %s in replicaSet, stop all node registration", ctrlHost.c_str());
            return result;
        }

        HexLogInfo("%s is joined mongodb replicaSet", ctrlHost.c_str());
    }

    return 0;
}

static int
CheckAndInitReplicaSet(std::vector<std::string> ctrlHosts)
{
    for (auto ctrlHost : ctrlHosts) {
        int result = HexUtilSystemF(FWD, 0, "mongosh --quiet mongodb://%s --eval \"db.hello().isWritablePrimary || db.hello().secondary\" | grep true", ctrlHost.c_str());
        if (result == 0) {
            HexLogInfo("replicaSet already inited on %s, skip replicaSet initializing", ctrlHost.c_str());
            return 0;
        }
    }

    return HexUtilSystemF(FWD, 0, "mongosh --quiet --eval 'rs.initiate()'");
}

static int
WaitActiveStatus()
{
    int period = 2;
    int count = 0;
    int limit = 60;

    while (true) {
        if (count >= limit) {
            break;
        }

        int result = HexUtilSystemF(FWD, 0, "mongosh --quiet --eval \"db.hello().ok\"");
        if (result == 0) {
            return 0;
        }

        HexLogWarning("Mongodb is starting, waiting for active status");
        sleep(period);
        count++;
    }

    return 1;
}

static bool
Commit(bool modified, int dryLevel)
{
    HEX_DRYRUN_BARRIER(dryLevel, true);
    if (!IsControl(s_eCubeRole) || !ShouldCommit(modified)) {
        return true;
    }

    SystemdCommitService(s_enabled, SERVICE, true);
    int result = WaitActiveStatus();
    if (result != 0) {
        HexLogError("failed to wait for the database to be active");
        return true;
    }

    std::vector<std::string> ctrlHosts = {s_hostname.c_str()};
    AppendCtrlPeerHostsIfObserved(ctrlHosts);

    result = CheckAndInitReplicaSet(ctrlHosts);
    if (result != 0) {
        HexLogError("failed to init mongodb replicaSet on %s", s_hostname.c_str());
        return true;
    }

    result = SyncHostsToReplicaSet(ctrlHosts);
    if (result != 0) {
        HexLogError("failed to add hosts to replicaSet");
        return true;
    }

    result = CheckAndInitAdminUser();
    if (result != 0) {
        HexLogError("failed to init mongodb users");
        return true;
    }

    WriteLogRotateConf(log_conf);

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_mongodb\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    Commit(true, DRYLEVEL_NONE);

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_mongodb, RestartMain, RestartUsage);

CONFIG_MODULE(mongodb, 0, Parse, 0, 0, Commit);
CONFIG_REQUIRES(mongodb, cube_scan);

CONFIG_OBSERVES(mongodb, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(mongodb, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(mongodb, DATA_DIR);

CONFIG_SUPPORT_COMMAND(HEX_SDK " mongodb_stats");
