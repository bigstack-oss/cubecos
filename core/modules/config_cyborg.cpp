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

// cyborg config files
#define DEF_EXT     ".def"
#define CONF        "/etc/cyborg/cyborg.conf"

static const char USER[] = "cyborg";
static const char GROUP[] = "cyborg";

// cyborg common
static const char RUNDIR[] = "/run/cyborg";
static const char LOGDIR[] = "/var/log/cyborg";

// cyborg services
static const char API_NAME[] = "cyborg-api";
static const char CDTR_NAME[] = "cyborg-conductor";
static const char AGENT_NAME[] = "cyborg-agent";

static const char OSCMD[] = "/usr/bin/openstack";
static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char USERPASS[] = "jfWRcIf8FOpFhX9L";
static const char DBPASS[] = "Ljug0Rdc2E5xFQdd";

static Configs cfg;

static bool s_bSetup = true;

static bool s_bCubeModified = false;
static bool s_bMqModified = false;
static bool s_bNovaModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bEndpointChanged = false;

static CubeRole_e s_eCubeRole;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("cyborg", "/var/log/cyborg/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(CYBORG_ENABLED, "cyborg.enabled", TUNING_UNPUB, "Set to true to enable cyborg.", true);
CONFIG_TUNING_STR(CYBORG_USERPASS, "cyborg.user.password", TUNING_UNPUB, "Set cyborg user password.", USERPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CYBORG_DBPASS, "cyborg.db.password", TUNING_UNPUB, "Set cyborg db password.", DBPASS, ValidateRegex, DFT_REGEX_STR);

// public tunigns
CONFIG_TUNING_BOOL(CYBORG_DEBUG, "cyborg.debug.enabled", TUNING_PUB, "Set to true to enable cyborg verbose log.", false);

// using external tunings
CONFIG_TUNING_SPEC_STR(RABBITMQ_OPENSTACK_PASSWD);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_HOSTS);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(NOVA_PLACEPASS);
CONFIG_TUNING_SPEC_STR(NOVA_USERPASS);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, CYBORG_ENABLED);
PARSE_TUNING_BOOL(s_debug, CYBORG_DEBUG);
PARSE_TUNING_STR(s_userPass, CYBORG_USERPASS);
PARSE_TUNING_STR(s_dbPass, CYBORG_USERPASS);
PARSE_TUNING_X_STR(s_mqPass, RABBITMQ_OPENSTACK_PASSWD, 1);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 2);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 2);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 2);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 2);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 2);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 2);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 2);
PARSE_TUNING_X_STR(s_placePass, NOVA_PLACEPASS, 3);
PARSE_TUNING_X_STR(s_novaPass, NOVA_USERPASS, 3);

// should run after mysql services are running.
static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if(!MysqlUtilIsDbExist("cyborg")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE cyborg") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON cyborg.* TO 'cyborg'@'localhost' IDENTIFIED BY 'cyborg_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON cyborg.* TO 'cyborg'@'%' IDENTIFIED BY 'cyborg_dbpass'")) {
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

    HexLogInfo("Setting up cyborg");

    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"cyborg-dbsync --config-file /etc/cyborg/cyborg.conf upgrade\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the cyborg service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s cyborg",
                         env.c_str(), OSCMD, domain.c_str(), userPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user cyborg admin", env.c_str(), OSCMD);

    HexUtilSystemF(0, 0, "%s %s service create --name cyborg "
                         "--description \"Acceleration Service\" accelerator",
                         env.c_str(), OSCMD);

    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating cyborg endpoint");

    std::string pub = "http://" + external + ":6666/v2";
    std::string adm = "http://" + endpoint + ":6666/v2";
    std::string intr = "http://" + endpoint + ":6666/v2";

    HexUtilSystemF(0, 0, "/usr/sbin/hex_sdk os_endpoint_update %s %s %s %s %s",
                         "accelerator", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static bool
UpdateDbConn(std::string sharedId, std::string password)
{
    if(IsControl(s_eCubeRole)) {
        std::string dbconn = "mysql+pymysql://cyborg:";
        dbconn += password;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/cyborg";

        cfg["database"]["connection"] = dbconn;
    }

    return true;
}

static bool
UpdateMqConn(const bool ha, std::string sharedId, std::string password, std::string ctrlAddrs)
{
    if (IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) {
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
        cfg["api"]["host_ip "] = myip;
    }

    return true;
}

static bool
UpdateSharedId(std::string sharedId)
{
    if(IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) {
        cfg["keystone_authtoken"]["memcached_servers"] = sharedId + ":11211";
        cfg["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["service_catalog"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["placement"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["nova"]["auth_url"] = "http://" + sharedId + ":5000";
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
UpdateCfg(const std::string& domain, const std::string& userPass, const std::string& plaPass, const std::string& novaPass)
{
    if(IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) {
        cfg["DEFAULT"]["log_dir"] = LOGDIR;
        cfg["DEFAULT"]["auth_strategy"] = "keystone";

        cfg["agent"]["enabled_drivers"] = "nvidia_gpu_driver";

        cfg["service_catalog"].clear();
        cfg["service_catalog"]["auth_type"] = "password";
        cfg["service_catalog"]["project_domain_name"] = domain;
        cfg["service_catalog"]["user_domain_name"] = domain;
        cfg["service_catalog"]["project_name"] = "service";
        cfg["service_catalog"]["username"] = "cyborg";
        cfg["service_catalog"]["password"] = userPass;

        cfg["placement"].clear();
        cfg["placement"]["auth_type"] = "password";
        cfg["placement"]["project_domain_name"] = domain;
        cfg["placement"]["user_domain_name"] = domain;
        cfg["placement"]["project_name"] = "service";
        cfg["placement"]["username"] = "placement";
        cfg["placement"]["password"] = plaPass;
        cfg["placement"]["auth_section"] = "keystone_authtoken";

        cfg["nova"].clear();
        cfg["nova"]["auth_type"] = "password";
        cfg["nova"]["project_domain_name"] = domain;
        cfg["nova"]["user_domain_name"] = domain;
        cfg["nova"]["project_name"] = "service";
        cfg["nova"]["username"] = "nova";
        cfg["nova"]["password"] = novaPass;
        cfg["nova"]["auth_section"] = "keystone_authtoken";

        cfg["keystone_authtoken"].clear();
        cfg["keystone_authtoken"]["auth_type"] = "password";
        cfg["keystone_authtoken"]["project_domain_name"] = domain;
        cfg["keystone_authtoken"]["user_domain_name"] = domain;
        cfg["keystone_authtoken"]["project_name"] = "service";
        cfg["keystone_authtoken"]["username"] = "cyborg";
        cfg["keystone_authtoken"]["password"] = userPass;

        cfg["oslo_messaging_notifications"]["driver"] = "messagingv2";

        if (IsControl(s_eCubeRole)) {
            std::string workers = std::to_string(GetControlWorkers(IsConverged(s_eCubeRole), IsEdge(s_eCubeRole)));
            cfg["api"]["api_workers"] = workers;
            cfg["api"]["port"] = "6666";
        }
    }

    return true;
}

static bool
CommitService(bool enabled)
{
    if (IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled, API_NAME, true);     // cyborg-api
        SystemdCommitService(enabled, CDTR_NAME, true);    // cyborg-conductor
    }

    if (IsCompute(s_eCubeRole)) {
        SystemdCommitService(enabled, AGENT_NAME, true);   // cyborg-agent
    }

    return true;
}

static bool
Init()
{
    if (HexMakeDir(RUNDIR, USER, GROUP, 0755) != 0)
        return false;

    // load cyborg configurations
    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', cfg)) {
        HexLogError("failed to load cyborg config file %s", CONF DEF_EXT);
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

static bool
ParseNova(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 3);
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

static void
NotifyNova(bool modified)
{
    s_bNovaModified = s_placePass.modified() | s_novaPass.modified();
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

    s_bConfigChanged = modified | s_bMqModified | s_bCubeModified | s_bNovaModified |
                               G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID);

    s_bEndpointChanged = s_bCubeModified | G_MOD(SHARED_ID) | G_MOD(EXTERNAL);

    return s_bDbPassChanged | s_bConfigChanged | s_bEndpointChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = s_enabled;
    std::string myip = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    std::string userPass = GetSaltKey(s_saltkey, s_userPass, s_seed);
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass, s_seed);
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass, s_seed);
    std::string placePass = GetSaltKey(s_saltkey, s_placePass.newValue(), s_seed.newValue());
    std::string novaPass = GetSaltKey(s_saltkey, s_novaPass.newValue(), s_seed.newValue());

    SetupCheck();
    if (!s_bSetup) {
        s_bDbPassChanged = true;
        s_bEndpointChanged = true;
    }

    if (s_bDbPassChanged && IsControl(s_eCubeRole))
        MysqlUtilUpdateDbPass(USER, dbPass.c_str());

    if (s_bConfigChanged) {
        UpdateCfg(s_cubeDomain, userPass, placePass, novaPass);
        UpdateSharedId(sharedId);
        UpdateMyIp(myip);
        UpdateDbConn(sharedId, dbPass);
        UpdateMqConn(s_ha, sharedId, mqPass, s_ctrlAddrs.newValue());
        UpdateDebug(s_debug);

        // write back to cyborg config file
        WriteConfig(CONF, SB_SEC_WFMT, '=', cfg);
    }

    // Service Setup (keystone service must be running)
    if (!s_bSetup)
        SetupService(s_cubeDomain, userPass);

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_cyborg_db");

    if (s_bEndpointChanged)
        UpdateEndpoint(sharedId, external, s_cubeRegion);

    CommitService(enabled);

    WriteLogRotateConf(log_conf);

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_cyborg\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    bool enabled = s_enabled;
    CommitService(enabled);

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_cyborg, RestartMain, RestartUsage);

CONFIG_MODULE(cyborg, Init, Parse, 0, 0, Commit);

// startup sequence
CONFIG_REQUIRES(cyborg, memcache);
CONFIG_REQUIRES(cyborg, nova);

// extra tunings
CONFIG_OBSERVES(cyborg, rabbitmq, ParseRabbitMQ, NotifyMQ);
CONFIG_OBSERVES(cyborg, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(cyborg, nova, ParseNova, NotifyNova);

