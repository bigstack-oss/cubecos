// CUBE

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/logrotate.h>
#include <hex/dryrun.h>

#include <cube/systemd_util.h>
#include <cube/config_file.h>
#include <cube/cluster.h>

#include "mysql_util.h"
#include "include/role_cubesys.h"

static const char USER[] = "masakari";
static const char GROUP[] = "masakari";

// masakari config files
#define DEF_EXT     ".def"
#define CONF        "/etc/masakari/masakari.conf"
#define MON_CONF    "/etc/masakarimonitors/masakarimonitors.conf"

// masakari-api
static const char API_NAME[] = "masakari-api";

// masakari-engine
static const char ENGINE_NAME[] = "masakari-engine";

// masakari-processmonitor
static const char PMON_NAME[] = "masakari-processmonitor";

// masakari-hostmonitor
static const char HMON_NAME[] = "masakari-hostmonitor";

// masakari-instancemonitor
static const char IMON_NAME[] = "masakari-instancemonitor";

static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char USERPASS[] = "C5rfkCpSfb9G4jiQ";
static const char DBPASS[] = "GRmeqOmBcyus5cW0";

static const char OSCMD[] = "/usr/bin/openstack";

static Configs cfg;
static Configs monCfg;

static ConfigString s_hostname;

static bool s_bSetup = true;

static bool s_bNetModified = false;
static bool s_bMqModified = false;
static bool s_bCubeModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bEndpointChanged = false;

static CubeRole_e s_eCubeRole;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("masakari", "/var/log/masakari/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(CTRL_IP);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(MASAKARI_ENABLED, "masakari.enabled", TUNING_UNPUB, "Set to true to enable masakari.", true);
CONFIG_TUNING_STR(MASAKARI_USERPASS, "masakari.user.password", TUNING_UNPUB, "Set masakari user password.", USERPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(MASAKARI_DBPASS, "masakari.db.password", TUNING_UNPUB, "Set masakari database password.", DBPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_BOOL(MASAKARI_DEBUG, "masakari.debug.enabled", TUNING_UNPUB, "Set to true to enable masakari verbose log.", false);

// public tunings
CONFIG_TUNING_BOOL(MASAKARI_HOST_EVA_ALL, "masakari.host.evacuate_all", TUNING_PUB, "Set to true to enable evacuate all instances when host goes down.", true);
CONFIG_TUNING_INT(MASAKARI_WAIT_PERIOD, "masakari.wait.period", TUNING_PUB, "Set wait period after service update", 0, 0, 99999);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(RABBITMQ_OPENSTACK_PASSWD);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_REGION);
CONFIG_TUNING_SPEC_STR(CUBESYS_MGMT);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, MASAKARI_ENABLED);
PARSE_TUNING_BOOL(s_debug, MASAKARI_DEBUG);
PARSE_TUNING_STR(s_masakariPass, MASAKARI_USERPASS);
PARSE_TUNING_STR(s_dbPass, MASAKARI_DBPASS);
PARSE_TUNING_BOOL(s_hostEvaAll, MASAKARI_HOST_EVA_ALL);
PARSE_TUNING_INT(s_waitPeriod, MASAKARI_WAIT_PERIOD);
PARSE_TUNING_X_STR(s_mqPass, RABBITMQ_OPENSTACK_PASSWD, 1);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 2);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 2);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 2);
PARSE_TUNING_X_STR(s_mgmt, CUBESYS_MGMT, 2);
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

    if(!MysqlUtilIsDbExist("masakari")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE masakari") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON masakari.* TO 'masakari'@'localhost' IDENTIFIED BY 'masakari_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON masakari.* TO 'masakari'@'%' IDENTIFIED BY 'masakari_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

// should run after keystone & mysql services are running.
static bool
SetupMasakari(std::string domain, std::string userPass)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up masakari");

    // Populate the masakari service database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"/usr/local/bin/masakari-manage db sync\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the masakari service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s masakari",
                         env.c_str(), OSCMD, domain.c_str(), userPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user masakari admin", env.c_str(), OSCMD);

    // Create the service entity
    HexUtilSystemF(0, 0, "%s %s service create --name masakari "
                         "--description \"masakari high availability\" ha",
                         env.c_str(), OSCMD);

    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating masakari endpoint");

    std::string pub = "http://" + external + ":15868/v1/%\\(tenant_id\\)s";
    std::string adm = "http://" + endpoint + ":15868/v1/%\\(tenant_id\\)s";
    std::string intr = "http://" + endpoint + ":15868/v1/%\\(tenant_id\\)s";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "ha", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static bool
UpdateDbConn(std::string sharedId, std::string password)
{
    if(IsControl(s_eCubeRole)) {
        std::string dbconn = "mysql+pymysql://masakari:";
        dbconn += password;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/masakari";

        cfg["database"]["connection"] = dbconn;
        cfg["taskflow"]["connection"] = dbconn;
    }

    return true;
}

static bool
UpdateControllerIp(std::string ctrlIp)
{
    if(IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["masakari_api_listen"] = ctrlIp;
    }

    return true;
}

static bool
UpdateSharedId(std::string sharedId)
{
    if(IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["os_privileged_user_auth_url"] = "http://" + sharedId + ":5000";
        cfg["keystone_authtoken"]["memcached_servers"] = sharedId + ":11211";
        cfg["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["oslo_messaging_notifications"]["transport_url"] = "kafka://" + sharedId + ":9095";
    }

    if (IsCompute(s_eCubeRole)) {
        monCfg["api"]["auth_url"] = "http://" + sharedId + ":5000";
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
UpdateDebug(bool enabled)
{
    std::string value = enabled ? "true" : "false";

    if(IsControl(s_eCubeRole))
        cfg["DEFAULT"]["debug"] = value;

    if(IsCompute(s_eCubeRole))
        monCfg["DEFAULT"]["debug"] = value;

    return true;
}


static bool
UpdateCfg(std::string region, std::string domain, std::string userPass, std::string hostname, std::string mgmtIf, bool hostEvaAll)
{
    if(IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["enabled_apis"] = "masakari_api";
        cfg["DEFAULT"]["masakari_api_listen_port"] = "15868";
        cfg["DEFAULT"]["log_dir"] = "/var/log/masakari";
        cfg["DEFAULT"]["auth_strategy"] = "keystone";
        cfg["DEFAULT"]["process_unfinished_notifications_interval"] = "120";
        cfg["DEFAULT"]["retry_notification_new_status_interval"] = "60";
        cfg["DEFAULT"]["wait_period_after_service_update"] = s_waitPeriod == 0 ? (IsEdge(s_eCubeRole) ? "30" : "180") : std::to_string(s_waitPeriod);
        cfg["DEFAULT"]["os_privileged_user_tenant"] = "service";
        cfg["DEFAULT"]["os_privileged_user_name"] = "masakari";
        cfg["DEFAULT"]["os_privileged_user_password"] = userPass;

        cfg["host_failure"]["evacuate_all_instances"] = hostEvaAll ? "true" : "false";
        cfg["host_failure"]["add_reserved_host_to_aggregate"] = "false";
        cfg["host_failure"]["ignore_instances_in_error_state"] = "false";

        cfg["instance_failure"]["process_all_instances"] = "false";

        cfg["wsgi"]["api_paste_config"] = "/etc/masakari/api-paste.ini";

        cfg["keystone_authtoken"].clear();
        cfg["keystone_authtoken"]["auth_type"] = "password";
        cfg["keystone_authtoken"]["project_domain_name"] = domain;
        cfg["keystone_authtoken"]["user_domain_name"] = domain;
        cfg["keystone_authtoken"]["project_name"] = "service";
        cfg["keystone_authtoken"]["username"] = "masakari";
        cfg["keystone_authtoken"]["password"] = userPass;

        cfg["oslo_messaging_notifications"]["driver"] = "messagingv2";
    }

    if (IsCompute(s_eCubeRole)) {
        monCfg["DEFAULT"]["log_dir"] = "/var/log/masakari";
        monCfg["DEFAULT"]["host"] = hostname;

        monCfg["api"].clear();
        monCfg["api"]["region"] = region;
        monCfg["api"]["api_version"] = "v1";
        monCfg["api"]["project_domain_name"] = domain;
        monCfg["api"]["user_domain_name"] = domain;
        monCfg["api"]["project_name"] = "service";
        monCfg["api"]["username"] = "masakari";
        monCfg["api"]["password"] = userPass;

        monCfg["host"]["disable_ipmi_check"] = "true";
        monCfg["host"]["corosync_multicast_interfaces"] = mgmtIf;
        monCfg["host"]["corosync_multicast_ports"] = "5405";
        monCfg["host"]["restrict_to_remotes"] = "true";
    }

    if (IsControl(s_eCubeRole)) {
        std::string workers = std::to_string(GetControlWorkers(IsConverged(s_eCubeRole), IsEdge(s_eCubeRole)));
        cfg["DEFAULT"]["masakari_api_workers"] = workers;
    }

    return true;
}

static bool
MasakariService(const bool enabled)
{
    if(IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled, API_NAME);
        SystemdCommitService(enabled, ENGINE_NAME);
    }

    if(IsCompute(s_eCubeRole)) {
        SystemdCommitService(enabled, IMON_NAME);
        SystemdCommitService(enabled, PMON_NAME);
        SystemdCommitService(enabled, HMON_NAME);
    }

    return true;
}

static bool
Init()
{
    // load masakari configurations
    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', cfg)) {
        HexLogError("failed to load masakari config file %s", CONF);
        return false;
    }

    if (!LoadConfig(MON_CONF DEF_EXT, SB_SEC_RFMT, '=', monCfg)) {
        HexLogError("failed to load masakari-monitors config file %s", MON_CONF);
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
ParseNet(const char *name, const char *value, bool isNew)
{
    if (strcmp(name, NET_HOSTNAME) == 0) {
        s_hostname.parse(value, isNew);
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
NotifyNet(bool modified)
{
    s_bNetModified = s_hostname.modified();
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
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        s_bConfigChanged = true;
        return true;
    }

    s_bDbPassChanged = s_dbPass.modified() | s_bCubeModified;

    s_bConfigChanged = modified | s_bMqModified |
                s_bCubeModified | s_bNetModified |
                 G_MOD(CTRL_IP) | G_MOD(SHARED_ID);

    s_bEndpointChanged = s_bCubeModified | s_bNetModified |
                        G_MOD(SHARED_ID) | G_MOD(EXTERNAL);

    return s_bDbPassChanged | s_bConfigChanged | s_bEndpointChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    std::string ctrlIp = G(CTRL_IP);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    std::string masakariPass = GetSaltKey(s_saltkey, s_masakariPass.newValue(), s_seed.newValue());
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass.newValue(), s_seed.newValue());

    SetupCheck();
    if (!s_bSetup) {
        s_bDbPassChanged = true;
        s_bEndpointChanged = true;
    }

    // update mysql db user password
    if (s_bDbPassChanged && IsControl(s_eCubeRole))
        MysqlUtilUpdateDbPass(USER, dbPass.c_str());

    // update config file
    if (s_bConfigChanged) {
        UpdateCfg(s_cubeRegion, s_cubeDomain, masakariPass, s_hostname, s_mgmt, s_hostEvaAll);
        UpdateSharedId(sharedId);
        UpdateControllerIp(ctrlIp);
        UpdateDbConn(sharedId, dbPass);
        UpdateMqConn(s_ha, sharedId, mqPass, s_ctrlAddrs.newValue());
        UpdateDebug(s_debug.newValue());

        WriteConfig(CONF, SB_SEC_WFMT, '=', cfg);
        WriteConfig(MON_CONF, SB_SEC_WFMT, '=', monCfg);
    }

    // configuring openstack sevice
    if (!s_bSetup)
        SetupMasakari(s_cubeDomain.newValue(), masakariPass);

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_masakari_db");

    // configuring openstack end point
    if (s_bEndpointChanged)
        UpdateEndpoint(sharedId, external, s_cubeRegion.newValue());

    // service kick off
    MasakariService(s_enabled);

    WriteLogRotateConf(log_conf);

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_masakari\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    MasakariService(s_enabled);

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_masakari, RestartMain, RestartUsage);

CONFIG_MODULE(masakari, Init, Parse, 0, 0, Commit);
// startup sequence
CONFIG_REQUIRES(masakari, memcache);

// extra tunings
CONFIG_OBSERVES(masakari, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(masakari, rabbitmq, ParseRabbitMQ, NotifyMQ);
CONFIG_OBSERVES(masakari, cubesys, ParseCube, NotifyCube);

