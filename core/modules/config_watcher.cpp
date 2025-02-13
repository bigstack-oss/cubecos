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

// watcher config files
#define DEF_EXT     ".def"
#define CONF        "/etc/watcher/watcher.conf"

static const char USER[] = "watcher";
static const char GROUP[] = "watcher";

// watcher common
static const char RUNDIR[] = "/run/watcher";
static const char LOGDIR[] = "/var/log/watcher";

// watcher services
static const char API_NAME[] = "openstack-watcher-api";
static const char ENGINE_NAME[] = "openstack-watcher-decision-engine";
static const char APPLIER_NAME[] = "openstack-watcher-applier";

static const char OSCMD[] = "/usr/bin/openstack";
static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char USERPASS[] = "Kjba1ugwByLdEugp";
static const char DBPASS[] = "p0dolvduWgBGBr9O";

static Configs cfg;

static bool s_bSetup = true;

static bool s_bCubeModified = false;
static bool s_bMqModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bEndpointChanged = false;

static CubeRole_e s_eCubeRole;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("openstack-watcher", "/var/log/watcher/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(WATCHER_ENABLED, "watcher.enabled", TUNING_UNPUB, "Set to true to enable watcher.", true);
CONFIG_TUNING_STR(WATCHER_USERPASS, "watcher.user.password", TUNING_UNPUB, "Set watcher user password.", USERPASS, ValidateNone);
CONFIG_TUNING_STR(WATCHER_DBPASS, "watcher.db.password", TUNING_UNPUB, "Set watcher db password.", DBPASS, ValidateNone);

// public tunigns
CONFIG_TUNING_BOOL(WATCHER_DEBUG, "watcher.debug.enabled", TUNING_PUB, "Set to true to enable watcher verbose log.", false);

// using external tunings
CONFIG_TUNING_SPEC_STR(RABBITMQ_OPENSTACK_PASSWD);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_HOSTS);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, WATCHER_ENABLED);
PARSE_TUNING_BOOL(s_debug, WATCHER_DEBUG);
PARSE_TUNING_STR(s_userPass, WATCHER_USERPASS);
PARSE_TUNING_STR(s_dbPass, WATCHER_USERPASS);
PARSE_TUNING_X_STR(s_mqPass, RABBITMQ_OPENSTACK_PASSWD, 1);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 2);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 2);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 2);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 2);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 2);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 2);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 2);

// should run after mysql services are running.
static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if(!MysqlUtilIsDbExist("watcher")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE watcher") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON watcher.* TO 'watcher'@'localhost' IDENTIFIED BY 'watcher_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON watcher.* TO 'watcher'@'%' IDENTIFIED BY 'watcher_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

// Setup should run after keystone.
static bool
SetupService(std::string domain, std::string userPass)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up watcher");

    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"watcher-db-manage --config-file /etc/watcher/watcher.conf upgrade\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the watcher service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s watcher",
                         env.c_str(), OSCMD, domain.c_str(), userPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user watcher admin", env.c_str(), OSCMD);

    HexUtilSystemF(0, 0, "%s %s service create --name watcher "
                         "--description \"Infrastructure Optimization\" infra-optim",
                         env.c_str(), OSCMD);

    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating watcher endpoint");

    std::string pub = "http://" + external + ":9322";
    std::string adm = "http://" + endpoint + ":9322";
    std::string intr = "http://" + endpoint + ":9322";

    HexUtilSystemF(0, 0, "/usr/sbin/hex_sdk os_endpoint_update %s %s %s %s %s",
                         "infra-optim", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static bool
UpdateDbConn(std::string sharedId, std::string password)
{
    if(IsControl(s_eCubeRole)) {
        std::string dbconn = "mysql+pymysql://watcher:";
        dbconn += password;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/watcher";

        cfg["database"]["connection"] = dbconn;
    }

    return true;
}

static bool
UpdateMqConn(const bool ha, std::string sharedId, std::string password, std::string ctrlAddrs)
{
    if (IsControl(s_eCubeRole)) {
        std::string dbconn = RabbitMqServers(ha, sharedId, password, ctrlAddrs);
        cfg["DEFAULT"]["transport_url"] = dbconn;
        cfg["DEFAULT"]["rpc_response_timeout"] = "1200";

        if (ha) {
            cfg["oslo_messaging_rabbit"]["rabbit_retry_interval"] = "1";
            cfg["oslo_messaging_rabbit"]["rabbit_retry_backoff"] = "2";
            cfg["oslo_messaging_rabbit"]["amqp_durable_queues"] = "true";
            cfg["oslo_messaging_rabbit"]["rabbit_ha_queues"] = "true";
        }
    }

    return true;
}

static bool
UpdateMyIp(std::string myip)
{
    if(IsControl(s_eCubeRole)) {
        cfg["api"]["host"] = myip;
    }

    return true;
}

static bool
UpdateSharedId(std::string sharedId)
{
    if(IsControl(s_eCubeRole)) {
        cfg["keystone_authtoken"]["memcached_servers"] = sharedId + ":11211";
        cfg["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["watcher_clients_auth"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["oslo_messaging_notifications"]["transport_url"] = "kafka://" + sharedId + ":9095";
    }

    return true;
}

static bool
UpdateDebug(bool enabled)
{
    std::string value = enabled ? "true" : "false";
    cfg["DEFAULT"]["debug"] = value;

    return true;
}

static bool
UpdateCfg(const std::string& domain, const std::string& userPass)
{
    if(IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["log_dir"] = LOGDIR;
        cfg["DEFAULT"]["auth_strategy"] = "keystone";
        cfg["DEFAULT"]["control_exchange"] = "watcher";

        cfg["api"]["port"] = "9322";

        cfg["keystone_authtoken"].clear();
        cfg["keystone_authtoken"]["auth_type"] = "password";
        cfg["keystone_authtoken"]["project_domain_name"] = domain;
        cfg["keystone_authtoken"]["user_domain_name"] = domain;
        cfg["keystone_authtoken"]["project_name"] = "service";
        cfg["keystone_authtoken"]["username"] = "watcher";
        cfg["keystone_authtoken"]["password"] = userPass;
        cfg["keystone_authtoken"]["service_token_roles_required"] = "true";

        cfg["watcher_clients_auth"].clear();
        cfg["watcher_clients_auth"]["auth_type"] = "password";
        cfg["watcher_clients_auth"]["project_domain_name"] = domain;
        cfg["watcher_clients_auth"]["user_domain_name"] = domain;
        cfg["watcher_clients_auth"]["project_name"] = "service";
        cfg["watcher_clients_auth"]["username"] = "watcher";
        cfg["watcher_clients_auth"]["password"] = userPass;

        cfg["watcher_datasources"]["datasources"] = "monasca";

        cfg["oslo_messaging_notifications"]["driver"] = "messagingv2";

        if (IsControl(s_eCubeRole)) {
            std::string workers = std::to_string(GetControlWorkers(IsConverged(s_eCubeRole), IsEdge(s_eCubeRole)));
            cfg["api"]["workers"] = workers;
            cfg["watcher_decision_engine"]["max_workers"] = workers;
            cfg["watcher_applier"]["workers"] = workers;
        }
    }

    return true;
}

static bool
CommitService(bool enabled)
{
    if (IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled, API_NAME, true);     // watcher-api
        SystemdCommitService(enabled, ENGINE_NAME, true);  // watcher-decision-engine
        SystemdCommitService(enabled, APPLIER_NAME, true); // watcher-applier
    }

    return true;
}

static bool
Init()
{
    if (HexMakeDir(RUNDIR, USER, GROUP, 0755) != 0)
        return false;

    // load watcher configurations
    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', cfg)) {
        HexLogError("failed to load watcher config file %s", CONF DEF_EXT);
        return false;
    }

    return true;
}

static bool
ParseRabbitMQ(const char *name, const char *value, bool isNew)
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
NotifyMQ(bool modified)
{
    s_bMqModified = IsModifiedTune(1);
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

    s_bConfigChanged = modified | s_bMqModified | s_bCubeModified |
                               G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID);

    s_bEndpointChanged = s_bCubeModified | G_MOD(SHARED_ID) | G_MOD(EXTERNAL);

    return s_bDbPassChanged | s_bConfigChanged | s_bEndpointChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (!IsControl(s_eCubeRole) || IsEdge(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = s_enabled;
    std::string myip = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    std::string userPass = GetSaltKey(s_saltkey, s_userPass, s_seed);
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass, s_seed);
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass, s_seed);

    SetupCheck();
    if (!s_bSetup) {
        s_bDbPassChanged = true;
        s_bEndpointChanged = true;
    }

    if (s_bDbPassChanged && IsControl(s_eCubeRole))
        MysqlUtilUpdateDbPass(USER, dbPass.c_str());

    if (s_bConfigChanged) {
        UpdateCfg(s_cubeDomain, userPass);
        UpdateSharedId(sharedId);
        UpdateMyIp(myip);
        UpdateDbConn(sharedId, dbPass);
        UpdateMqConn(s_ha, sharedId, mqPass, s_ctrlAddrs.newValue());
        UpdateDebug(s_debug);

        // write back to watcher config file
        WriteConfig(CONF, SB_SEC_WFMT, '=', cfg);
    }

    // Service Setup (keystone service must be running)
    if (!s_bSetup)
        SetupService(s_cubeDomain, userPass);

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_watcher_db");

    if (s_bEndpointChanged)
        UpdateEndpoint(sharedId, external, s_cubeRegion);

    CommitService(enabled);

    WriteLogRotateConf(log_conf);

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_watcher\n", HexLogProgramName());
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

CONFIG_COMMAND_WITH_SETTINGS(restart_watcher, RestartMain, RestartUsage);

CONFIG_MODULE(watcher, Init, Parse, 0, 0, Commit);

// startup sequence
CONFIG_REQUIRES(watcher, memcache);

// extra tunings
CONFIG_OBSERVES(watcher, rabbitmq, ParseRabbitMQ, NotifyMQ);
CONFIG_OBSERVES(watcher, cubesys, ParseCube, NotifyCube);

