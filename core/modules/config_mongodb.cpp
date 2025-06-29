// CUBE

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

static const char SERVICE[] = "mongodb";
static const char MONGODB_REPLICA_SET_NAME[] = "cube-cos-rs";
static const char MONGOD_CONF_IN[] = "/etc/mongod.conf.in";
static const char MONGOD_CONF[] = "/etc/mongod.conf";
static const char MONGODB_CONF_DIR[] = "/etc/mongodb";
static const char MONGODB_KEYFILE[] = "/etc/mongodb/keyfile";
static const int MONGODB_KEYFILE_MIN_LENGTH = 6;
static const int MONGODB_KEYFILE_MAX_LENGTH = 1024;
static const char MONGODB_ADMIN_ACCESS[] = "/etc/mongodb/admin-access.sh";
static const char DATA_DIR[] = "/var/lib/mongo";
static const char MARKER_MONGODB_RS_CREATED[] = "/etc/appliance/state/mongodb_rs_created";

static const char USER[] = "mongod";
static const char GROUP[] = "mongod";
static const char MONGODB_DBPASS_DEFAULT[] = "tp7cmpFO4DffM2NI";

static bool s_bCubeModified = false;
static bool s_bNetModified = false;

static ConfigString s_hostname;
static CubeRole_e s_eCubeRole;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("mongodb", "/var/log/mongodb/*.log", DAILY, 128, 0, true);

// private tunings
CONFIG_TUNING_BOOL(MONGODB_ENABLED, "mongodb.enabled", TUNING_UNPUB, "Set to true to enable mongodb.", true);
CONFIG_TUNING_STR(MONGODB_DBKEY, "mongodb.key", TUNING_UNPUB, "Set mongodb replica set key.", MONGODB_DBPASS_DEFAULT, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(MONGODB_DBPASS, "mongodb.password", TUNING_UNPUB, "Set mongodb password.", MONGODB_DBPASS_DEFAULT, ValidateRegex, DFT_REGEX_STR);

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_BOOL_REF(IS_MASTER);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_HOSTS);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, MONGODB_ENABLED);
PARSE_TUNING_STR(s_dbKey, MONGODB_DBKEY);
PARSE_TUNING_STR(s_dbPass, MONGODB_DBPASS);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_ctrlHosts, CUBESYS_CONTROL_HOSTS, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 1);

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
Init()
{
    if (HexMakeDir(MONGODB_CONF_DIR, USER, GROUP, 0755) != 0) {
        HexLogError("failed to create %s", MONGODB_CONF_DIR);
        return false;
    }

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
ShouldCommit(bool modified)
{
    if (IsBootstrap()) {
        return true;
    }

    return modified | s_bCubeModified | s_bNetModified | G_MOD(MGMT_ADDR) | G_MOD(IS_MASTER) | s_dbPass.modified();
}

static bool
WriteMongodConf(bool enableAuth, const char* myip)
{
    if (access(MONGOD_CONF_IN, R_OK) != 0) {
        return false;
    }

    if (enableAuth) {
        if (HexUtilSystemF(0, 0, "sed -e \"s/@MGMT_ADDR@/%s/\" -e \"s/@SECURITY_START@//\" -e \"s/@SECURITY_END@//\" %s > %s", myip, MONGOD_CONF_IN, MONGOD_CONF) != 0) {
            HexLogError("failed to update %s", MONGOD_CONF);
            return false;
        }
    } else {
        // remove the security configuration here to remove the authentication
        if (HexUtilSystemF(0, 0, "sed -e \"s/@MGMT_ADDR@/%s/\" -e \"/@SECURITY_START@/,/@SECURITY_END@/d\" %s > %s", myip, MONGOD_CONF_IN, MONGOD_CONF) != 0) {
            HexLogError("failed to update %s", MONGOD_CONF);
            return false;
        }
    }

    return true;
}

static bool
WriteMongodKeyfile(std::string key)
{
    FILE *fout = fopen(MONGODB_KEYFILE, "w");
    if (!fout) {
        HexLogError("Unable to write mongodb keyfile: %s", MONGODB_KEYFILE);
        return false;
    }
    fprintf(fout, key.c_str());
    fclose(fout);

    HexSetFileMode(MONGODB_KEYFILE, USER, GROUP, 0400);
    return true;
}

/**
 * Return the admin access for MongoDB.
 * If the admin access is not yet set up, "" would be returned.
 * Otherwise, "admin:<password>@" would be returned.
 * For being used in "mongodb://<return_value><binding_ip>:<binding_port>".
 */
static std::string
GetAdminAccess()
{
    if (access(MONGODB_ADMIN_ACCESS, R_OK) != 0) {
        return "";
    }

    FILE *fin = fopen(MONGODB_ADMIN_ACCESS, "r");
    if (!fin) {
        HexLogError("could not read mongodb admin access %s", MONGODB_ADMIN_ACCESS);
        return "";
    }

    char *buffer = NULL;
    std::size_t bufferSize = 0;
    if (getline(&buffer, &bufferSize, fin) < 0) {
        return "";
    }

    std::vector<std::string> fileContents = hex_string_util::split(std::string(buffer), '=');
    if (fileContents.size() < 2) {
        return "";
    }

    std::string adminAccess = fileContents.at(1);
    if (adminAccess.size() == 0) {
        return "";
    }

    std::stringstream output;
    output << "admin:" << adminAccess << "@";
    return output.str();
}

static bool
WriteAdminAccess(std::string dbPass)
{
    // update the mongodb admin access
    FILE *fout = fopen(MONGODB_ADMIN_ACCESS, "w");
    if (!fout) {
        HexLogError("Unable to write mongodb admin access: %s", MONGODB_ADMIN_ACCESS);
        return 1;
    }
    fprintf(fout, "export MONGODB_ADMIN_ACCESS=%s", dbPass.c_str());
    fclose(fout);

    return true;
}

static int
WaitActiveStatus(std::string myip)
{
    int period = 2;
    int count = 0;
    int limit = 60;

    while (true) {
        if (count >= limit) {
            break;
        }

        int result = HexUtilSystemF(
            FWD,
            0,
            "mongosh mongodb://%s --quiet --eval \"db.hello().ok\"",
            myip.c_str()
        );
        if (result == 0) {
            return 0;
        }

        HexLogWarning("Mongodb is starting, waiting for active status");
        sleep(period);
        count++;
    }

    return 1;
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
CheckAndInitReplicaSet(std::vector<std::string> ctrlHosts, std::string myip, const char* myHostName)
{
    for (auto ctrlHost : ctrlHosts) {
        int result = HexUtilSystemF(
            0,
            0,
            "mongosh mongodb://%s --quiet --eval 'db.hello().isWritablePrimary || db.hello().secondary' | grep -q true",
            ctrlHost.c_str()
        );
        if (result == 0) {
            HexLogInfo("replicaSet already inited on %s, skip replicaSet initializing", ctrlHost.c_str());
            return 0;
        }
    }

    return HexUtilSystemF(
        FWD,
        0,
        "mongosh mongodb://%s --quiet --eval 'rs.initiate({_id:\"%s\",members:[{_id:0,host:\"%s\"}]})'",
        myip.c_str(),
        MONGODB_REPLICA_SET_NAME,
        myHostName
    );
}

static bool
IsHostRegistered(char* host, std::string myip)
{
    int result = HexUtilSystemF(
        0,
        0,
        "mongosh mongodb://%s --quiet --eval 'JSON.stringify(rs.conf().members)' | jq '([.[] | select(.host == \"%s:27017\")] | length) > 0' | grep -q true",
        myip.c_str(),
        host
    );
    if (result == 0) {
        return true;
    }

    return false;
}

static int
SyncHostsToReplicaSet(std::vector<std::string>& ctrlHosts, std::string myip)
{
    for (auto ctrlHost : ctrlHosts) {
        if (IsHostRegistered(const_cast<char*>(ctrlHost.c_str()), myip)) {
            HexLogInfo("%s is already added in replicaSet, skip adding", ctrlHost.c_str());
            continue;
        }

        int result = HexUtilSystemF(
            FWD,
            0,
            "mongosh mongodb://%s --quiet --eval 'rs.add(\"%s\")'",
            myip.c_str(),
            ctrlHost.c_str()
        );
        if (result != 0) {
            HexLogError("failed to add %s in replicaSet, stop all node registration", ctrlHost.c_str());
            return result;
        }

        HexLogInfo("%s has joined mongodb replicaSet", ctrlHost.c_str());
    }

    return 0;
}

static bool
CheckAdminUser(std::string mongodbUri)
{
    // check if admin user is created or not
    int result = HexUtilSystemF(
        0,
        0,
        "mongosh %s --quiet --eval 'db.getSiblingDB(\"admin\").getUser(\"admin\")' | grep -q admin",
        mongodbUri.c_str()
    );
    return (result == 0);
}

static bool
InitAdminUser(std::string myip, std::string dbPass)
{
    // create the admin user
    int result = HexUtilSystemF(
        FWD,
        0,
        "mongosh mongodb://%s --quiet --eval "
        "'db.getSiblingDB(\"admin\").createUser({"
        "user:\"admin\","
        "pwd:\"%s\","
        "roles:["
        "{role:\"userAdminAnyDatabase\",db:\"admin\"},"
        "{role:\"clusterAdmin\",db:\"admin\"},"
        "{role:\"readWriteAnyDatabase\",db:\"admin\"}"
        "]})'",
        myip.c_str(),
        dbPass.c_str()
    );
    return (result == 0);
}

static bool
UpdateAdminUser(std::string mongodbUri, std::string dbPass)
{
    // update the mongodb admin password
    int result = HexUtilSystemF(
        FWD,
        0,
        "mongosh %s --quiet --eval 'db.getSiblingDB(\"admin\").changeUserPassword(\"admin\", \"%s\")'",
        mongodbUri.c_str(),
        dbPass.c_str()
    );
    return (result == 0);
}

static bool
Commit(bool modified, int dryLevel)
{
    HEX_DRYRUN_BARRIER(dryLevel, true);
    if (!IsControl(s_eCubeRole) || !ShouldCommit(modified)) {
        return true;
    }

    std::string myip = G(MGMT_ADDR);
    bool dbPassChanged = s_saltkey.modified() || s_dbPass.modified() || s_seed.modified();
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());

    // create the mongodb keyfile for the replica set
    bool dbKeyChanged = s_saltkey.modified() || s_dbKey.modified() || s_seed.modified();
    if (access(MONGODB_KEYFILE, R_OK) != 0 || dbKeyChanged) {
        std::string dbKey = GetSaltKey(s_saltkey, s_dbKey.newValue(), s_seed.newValue());
        if (dbKey.length() < MONGODB_KEYFILE_MIN_LENGTH) {
            dbKey.append(MONGODB_KEYFILE_MIN_LENGTH - dbKey.length(), '0');
        } else if (dbKey.length() > MONGODB_KEYFILE_MAX_LENGTH) {
            dbKey.resize(MONGODB_KEYFILE_MAX_LENGTH);
        }

        if (!WriteMongodKeyfile(dbKey)) {
            HexLogError("failed to write mongodb key file");
            return true;
        }
    }

    // get the control host list
    std::vector<std::string> ctrlHosts = {s_hostname.c_str()};
    AppendCtrlPeerHostsIfObserved(ctrlHosts);

    // set up the replica set on the master node
    bool isMaster = G(IS_MASTER);
    if (isMaster && access(MARKER_MONGODB_RS_CREATED, F_OK) != 0) {
        // create the mongodb config without auth enabled
        if (!WriteMongodConf(false, myip.c_str())) {
            HexLogError("failed to set mongod config");
            return true;
        }

        // start mongodb
        SystemdCommitService(s_enabled, SERVICE, true);

        // wait for mongodb to be ready
        int result = WaitActiveStatus(myip);
        if (result != 0) {
            HexLogError("failed to wait for the database to be active");
            return true;
        }

        // initiate the replica set
        result = CheckAndInitReplicaSet(ctrlHosts, myip, s_hostname.c_str());
        if (result != 0) {
            HexLogError("failed to init mongodb replicaSet on %s", s_hostname.c_str());
            return true;
        }

        // add self to the replica set
        result = SyncHostsToReplicaSet(ctrlHosts, myip);
        if (result != 0) {
            HexLogError("failed to add hosts to replicaSet");
            return true;
        }

        // mark that mongodb replica set has been created
        HexSystemF(0, "touch %s", MARKER_MONGODB_RS_CREATED);

        if (!InitAdminUser(myip, dbPass)) {
            HexLogError("failed to create admin user");
            return true;
        }
    }

    // update the mongodb config with auth enabled
    if (!WriteMongodConf(true, myip.c_str())) {
        HexLogError("failed to set mongod config");
        return true;
    }

    // restart mongodb
    SystemdCommitService(s_enabled, SERVICE, true);
    WriteLogRotateConf(log_conf);

    // wait for mongodb to be ready
    int result = WaitActiveStatus(myip);
    if (result != 0) {
        HexLogError("failed to wait for the database to be active");
        return true;
    }

    // get the old admin access
    std::string oldAdminAccess = GetAdminAccess();

    // create mongodb uri with the replica set
    int index = 0;
    std::stringstream mongodbUri;
    mongodbUri << "mongodb://";
    if (oldAdminAccess != "") {
        mongodbUri << oldAdminAccess;
    } else {
        mongodbUri << "admin:" << dbPass << "@";
    }
    for (std::string c: ctrlHosts) {
        if (index != 0) {
            mongodbUri << ",";
        }
        mongodbUri << c;
        index++;
    }
    mongodbUri << "/?replicaSet=" << MONGODB_REPLICA_SET_NAME;
    std::string mongodbUriStr = mongodbUri.str();

    // update the admin user
    if (dbPassChanged && CheckAdminUser(mongodbUriStr)) {
        if (!UpdateAdminUser(mongodbUriStr, dbPass)) {
            HexLogError("failed to update mongodb admin password");
            return true;
        }
    }

    // write the dbPass as mongodb admin access
    if (!WriteAdminAccess(dbPass)) {
        HexLogError("failed to write mongodb admin access");
        return true;
    }

    // sync mongodb admin access across the cluster control nodes
    if (GetAdminAccess() != "") {
        HexUtilSystemF(0, 0, "cubectl node rsync --role=control %s", MONGODB_ADMIN_ACCESS);
    }

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

CONFIG_MODULE(mongodb, Init, Parse, 0, 0, Commit);
CONFIG_REQUIRES(mongodb, cube_scan);

CONFIG_OBSERVES(mongodb, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(mongodb, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(mongodb, MARKER_MONGODB_RS_CREATED);
CONFIG_MIGRATE(mongodb, DATA_DIR);

CONFIG_SUPPORT_COMMAND(HEX_SDK " mongodb_stats");
