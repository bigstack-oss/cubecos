// CUBE

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>

#include <cube/config_file.h>
#include <cube/cluster.h>

#include "mysql_util.h"
#include "include/role_cubesys.h"

static const char USER[] = "barbican";
static const char GROUP[] = "barbican";

// barbican config files
#define DEF_EXT     ".def"
#define CONF        "/etc/barbican/barbican.conf"

// barbican common
static const char RUNDIR[] = "/run/barbican";

// barbican-api
static const char API_NAME[] = "barbican-api";

// barbican-engine
static const char ENGINE_NAME[] = "barbican-engine";

static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char USERPASS[] = "0jtLcw028IYRjIMd";
static const char DBPASS[] = "tp7FcmpO4fSfM2NI";
static const char CRYPTOPASS[] = "paA7W6gtT3lHXJBb";

static const char OSCMD[] = "/usr/bin/openstack";

static Configs cfg;

static bool s_bSetup = true;

static bool s_bMqModified = false;
static bool s_bCubeModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bEndpointChanged = false;

static CubeRole_e s_eCubeRole;

// external global variables
CONFIG_GLOBAL_STR_REF(CTRL_IP);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(BARBICAN_ENABLED, "barbican.enabled", TUNING_UNPUB, "Set to true to enable barbican.", true);
CONFIG_TUNING_STR(BARBICAN_USERPASS, "barbican.user.password", TUNING_UNPUB, "Set barbican user password.", USERPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(BARBICAN_DBPASS, "barbican.db.password", TUNING_UNPUB, "Set barbican database password.", DBPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(BARBICAN_CRYPTOPASS, "barbican.crypto.password", TUNING_UNPUB, "Set barbican crypto password.", CRYPTOPASS, ValidateRegex, DFT_REGEX_STR);

// public tunings
CONFIG_TUNING_BOOL(BARBICAN_DEBUG, "barbican.debug.enabled", TUNING_PUB, "Set to true to enable barbican verbose log.", false);

// using external tunings
CONFIG_TUNING_SPEC_STR(RABBITMQ_OPENSTACK_PASSWD);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_REGION);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, BARBICAN_ENABLED);
PARSE_TUNING_BOOL(s_debug, BARBICAN_DEBUG);
PARSE_TUNING_STR(s_barbicanPass, BARBICAN_USERPASS);
PARSE_TUNING_STR(s_dbPass, BARBICAN_DBPASS);
PARSE_TUNING_STR(s_cryptoPass, BARBICAN_CRYPTOPASS);
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

    if(!MysqlUtilIsDbExist("barbican")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE barbican") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON barbican.* TO 'barbican'@'localhost' IDENTIFIED BY 'barbican_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON barbican.* TO 'barbican'@'%' IDENTIFIED BY 'barbican_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

// should run after keystone & mysql services are running.
static bool
SetupBarbican(std::string domain, std::string userPass)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up barbican");

    // Populate the barbican service database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"barbican-manage db upgrade\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the barbican service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s barbican",
                         env.c_str(), OSCMD, domain.c_str(), userPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user barbican admin", env.c_str(), OSCMD);

    // Create a creator role
    HexUtilSystemF(0, 0, "%s %s role create creator", env.c_str(), OSCMD);
    HexUtilSystemF(0, 0, "%s %s role add --project service --user barbican creator", env.c_str(), OSCMD);

    // Create the service entity
    HexUtilSystemF(0, 0, "%s %s service create --name barbican "
                         "--description \"Key Manager\" key-manager",
                         env.c_str(), OSCMD);

    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating barbican endpoint");

    std::string pub = "http://" + external + ":9311";
    std::string adm = "http://" + endpoint + ":9311";
    std::string intr = "http://" + endpoint + ":9311";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "key-manager", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static bool
UpdateDbConn(std::string sharedId, std::string password)
{
    if(IsControl(s_eCubeRole)) {
        std::string dbconn = "mysql+pymysql://barbican:";
        dbconn += password;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/barbican";

        cfg["DEFAULT"]["sql_connection"] = dbconn;
    }

    return true;
}

static bool
UpdateControllerIp(std::string ctrlIp)
{
    if(IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["bind_host"] = ctrlIp;
    }

    return true;
}

static bool
UpdateSharedId(std::string sharedId)
{
    if(IsControl(s_eCubeRole)) {
        cfg["keystone_authtoken"]["memcached_servers"] = sharedId + ":11211";
        cfg["DEFAULT"]["host_href"] = "http://" + sharedId + ":9311";
        cfg["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["oslo_messaging_notifications"]["transport_url"] = "kafka://" + sharedId + ":9095";
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
    cfg["DEFAULT"]["debug"] = value;

    return true;
}

static bool
UpdateCfg(std::string domain, std::string userPass, std::string cryptoPass)
{
    if(IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["bind_port"] = "9311";
        cfg["DEFAULT"]["log_dir"] = "/var/log/barbican";
        cfg["DEFAULT"]["backlog"] = "4096";
        cfg["DEFAULT"]["max_allowed_secret_in_bytes"] = "10000";
        cfg["DEFAULT"]["max_allowed_request_size_in_bytes"] = "1000000";
        cfg["DEFAULT"]["db_auto_create"] = "false";

        cfg["keystone_notifications"]["enable"] = "true";

        cfg["secretstore"]["namespace"] = "barbican.secretstore.plugin";
        cfg["secretstore"]["enabled_secretstore_plugins"] = "store_crypto";
        cfg["crypto"]["enabled_crypto_plugins"] = "simple_crypto";
        cfg["simple_crypto_plugin"]["kek"] = "'" + cryptoPass + "'";

        cfg["keystone_authtoken"].clear();
        cfg["keystone_authtoken"]["auth_type"] = "password";
        cfg["keystone_authtoken"]["project_domain_name"] = domain.c_str();
        cfg["keystone_authtoken"]["user_domain_name"] = domain.c_str();
        cfg["keystone_authtoken"]["project_name"] = "service";
        cfg["keystone_authtoken"]["username"] = "barbican";
        cfg["keystone_authtoken"]["password"] = userPass.c_str();

        cfg["oslo_messaging_notifications"]["driver"] = "messagingv2";
    }

    return true;
}

static bool
Init()
{
    if (HexMakeDir(RUNDIR, USER, GROUP, 0755) != 0)
        return false;

    // load barbican configurations
    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', cfg)) {
        HexLogError("failed to load barbican config file %s", CONF);
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
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        s_bConfigChanged = true;
        return true;
    }

    s_bDbPassChanged = s_dbPass.modified() | s_bCubeModified;

    s_bConfigChanged = modified | s_bMqModified | s_bCubeModified |
                       G_MOD(CTRL_IP) | G_MOD(SHARED_ID);

    s_bEndpointChanged = s_bCubeModified | G_MOD(SHARED_ID) | G_MOD(EXTERNAL);

    return s_bDbPassChanged | s_bConfigChanged | s_bEndpointChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || IsEdge(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    std::string ctrlIp = G(CTRL_IP);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    std::string barbicanPass = GetSaltKey(s_saltkey, s_barbicanPass.newValue(), s_seed.newValue());
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass.newValue(), s_seed.newValue());
    std::string cryptoPass = GetSaltBytesInBase64(s_saltkey, 32, s_cryptoPass.newValue(), s_seed.newValue());

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
        UpdateCfg(s_cubeDomain.newValue(), barbicanPass, cryptoPass);
        UpdateSharedId(sharedId);
        UpdateControllerIp(ctrlIp);
        UpdateDbConn(sharedId, dbPass);
        UpdateMqConn(s_ha, sharedId, mqPass, s_ctrlAddrs.newValue());
        UpdateDebug(s_debug.newValue());

        WriteConfig(CONF, SB_SEC_WFMT, '=', cfg);
    }

    // configuring openstack sevice
    if (!s_bSetup)
        SetupBarbican(s_cubeDomain.newValue(), barbicanPass);

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_barbican_db");

    // configuring openstack end point
    if (s_bEndpointChanged)
        UpdateEndpoint(sharedId, external, s_cubeRegion.newValue());

    // barbican-api service run along with httpd

    return true;
}

CONFIG_MODULE(barbican, Init, Parse, 0, 0, Commit);
// startup sequence
CONFIG_REQUIRES(barbican, memcache);

// extra tunings
CONFIG_OBSERVES(barbican, rabbitmq, ParseRabbitMQ, NotifyMQ);
CONFIG_OBSERVES(barbican, cubesys, ParseCube, NotifyCube);

