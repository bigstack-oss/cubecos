// CUBE SDK

#include "include/constant.h"
#include "include/role_cubesys.h"
#include "mysql_util.h"
#include <cluster.hpp>
#include <cube/config_file.h>
#include <cube/systemd_util.h>
#include <hex/config_global.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/dryrun.h>
#include <hex/filesystem.h>
#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/string_util.h>

// config files
#define CONF "/etc/manila/manila.conf"
#define INIT_DONE "/etc/appliance/state/manila_init_done"

static const char USER[] = "manila";
static const char GROUP[] = "manila";
static const char LOCKDIR[] = "/var/lock/manila";

// manila-api
static const char API_NAME[] = "openstack-manila-api";
// manila-scheduler
static const char SCHEDULER_NAME[] = "openstack-manila-scheduler";
// manila-share
static const char SHARE_NAME[] = "openstack-manila-share";

static const char OPENRC[] = "/etc/admin-openrc.sh";
static const char OSCMD[] = "/usr/bin/openstack";

static const char USERPASS[] = "iSH2oRU3cwyOG6vj";
static const char DBPASS[] = "vSV8gnW0PtuFgnHA";

static const char HMGR_SYNC[] = "/etc/cron.d/manila_hmgr_sync";

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(MANILA_ENABLED, "manila.enabled", TUNING_UNPUB, "Set to true to enable manila.", true);
CONFIG_TUNING_STR(MANILA_USERPASS, "manila.user.password", TUNING_UNPUB, "Set manila user password.", USERPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(MANILA_DBPASS, "manila.db.password", TUNING_UNPUB, "Set manila database password.", DBPASS, ValidateRegex, DFT_REGEX_STR);

// public tunings
CONFIG_TUNING_BOOL(MANILA_DEBUG, "manila.debug.enabled", TUNING_PUB, "Set to true to enable manila verbose log.", false);
CONFIG_TUNING_STR(MANILA_VOLUME_TYPE, "manila.volume.type", TUNING_PUB, "Set manila backend volume type.", BUILTIN_VOLUME_TYPE, ValidateRegex, DFT_REGEX_STR);

// using external tunings
CONFIG_TUNING_SPEC_STR(RABBITMQ_OPENSTACK_PASSWD);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_REGION);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_STR(CUBESYS_MGMT_CIDR);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_STR(KEYSTONE_ADMIN_CLI_PASS);
CONFIG_TUNING_SPEC_STR(CINDER_VOLUME_TYPE_DEFAULT);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, MANILA_ENABLED);
PARSE_TUNING_BOOL(s_debug, MANILA_DEBUG);
PARSE_TUNING_STR(s_manilaPass, MANILA_USERPASS);
PARSE_TUNING_STR(s_dbPass, MANILA_DBPASS);
PARSE_TUNING_STR(s_volumeType, MANILA_VOLUME_TYPE);
PARSE_TUNING_X_STR(s_mqPass, RABBITMQ_OPENSTACK_PASSWD, 1);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 2);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 2);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 2);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 2);
PARSE_TUNING_X_STR(s_mgmtCidr, CUBESYS_MGMT_CIDR, 2);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 2);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 2);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 2);
PARSE_TUNING_X_STR(s_adminCliPass, KEYSTONE_ADMIN_CLI_PASS, 3);
PARSE_TUNING_X_STR(s_cinderVolumeTypeDefault, CINDER_VOLUME_TYPE_DEFAULT, 4);

static bool s_bSetup = true;

static bool s_bMqModified = false;
static bool s_bCubeModified = false;
static bool s_bKeystoneModified = false;
static bool s_bCinderModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bEndpointChanged = false;

static CubeRole_e s_eCubeRole;
static Configs config;

static bool
ParseRabbitMQ(const char* name, const char* value, bool isNew)
{
    ParseTune(name, value, isNew, 1);
    return true;
}

static void
NotifyMQ(bool modified)
{
    s_bMqModified = IsModifiedTune(1);
}

static bool
ParseCube(const char* name, const char* value, bool isNew)
{
    ParseTune(name, value, isNew, 2);
    return true;
}

static void
NotifyCube(bool modified)
{
    s_bCubeModified = IsModifiedTune(2);
    s_eCubeRole = GetCubeRole(s_cubeRole);
}

static bool
ParseKeystone(const char* name, const char* value, bool isNew)
{
    ParseTune(name, value, isNew, 3);
    return true;
}

static void
NotifyKeystone(bool modified)
{
    s_bKeystoneModified = IsModifiedTune(3);
}

static bool
ParseCinder(const char* name, const char* value, bool isNew)
{
    ParseTune(name, value, isNew, 4);
    return true;
}

static void
NotifyCinder(bool modified)
{
    s_bCinderModified = IsModifiedTune(4);
}

static bool
Init()
{
    // fail safe for creating manila lock dir
    HexMakeDir(LOCKDIR, USER, GROUP, 0755);

    return true;
}

static bool
Parse(const char* name, const char* value, bool isNew)
{
    bool r = true;

    TuneStatus s = ParseTune(name, value, isNew);
    if (s == TUNE_INVALID_NAME) {
        HexLogWarning("Unknown settings name \"%s\" = \"%s\" ignored", name, value);
    } else if (s == TUNE_INVALID_VALUE) {
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

    s_bDbPassChanged = s_dbPass.modified()
        || s_bCubeModified;

    s_bConfigChanged = modified
        || s_bMqModified
        || s_bCubeModified
        || s_bKeystoneModified
        || s_bCinderModified
        || G_MOD(MGMT_ADDR)
        || G_MOD(SHARED_ID);

    s_bEndpointChanged = s_bCubeModified
        || G_MOD(SHARED_ID)
        || G_MOD(EXTERNAL);

    return s_bDbPassChanged
        || s_bConfigChanged
        || s_bEndpointChanged;
}

/**
 * Check if the database is set up for Manila.
 */
static bool
IsDatabaseSetup()
{
    return MysqlUtilIsDbExist("manila");
}

/**
 * Set up the database for Manila.
 */
static bool
SetupDatabase()
{
    if (IsDatabaseSetup()) {
        return true;
    }

    if (!MysqlUtilRunSQL("CREATE DATABASE manila")
        || !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON manila.* TO 'manila'@'localhost' IDENTIFIED BY 'MANILA_DBPASS'")
        || !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON manila.* TO 'manila'@'%' IDENTIFIED BY 'MANILA_DBPASS'")) {
        return false;
    }

    return true;
}

/**
 * Load default configs.
 */
static bool
LoadDefaultConfig(Configs& config)
{
    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', config)) {
        HexLogError("Failed to load the default manila config file %s", CONF DEF_EXT);
        return false;
    }

    return true;
}

/**
 * Initiate the structure of the config.
 */
static void
InitConfig(Configs& config)
{
    std::vector<std::string> sections = std::vector<std::string> {
        "DEFAULT",
        "cinder",
        "cors",
        "database",
        "generic",
        "glance",
        "healthcheck",
        "keystone_authtoken",
        "neutron",
        "nova",
        "oslo_concurrency",
        "oslo_messaging_amqp",
        "oslo_messaging_kafka",
        "oslo_messaging_notifications",
        "oslo_messaging_rabbit",
        "oslo_middleware",
        "oslo_policy",
        "quota",
        "ssl",
    };

    SetupConfig(sections, config);
}

/**
 * Set the defaults of the config.
 */
static void
SetDefaults(Configs& config)
{
    config["DEFAULT"]["api_paste_config"] = "/etc/manila/api-paste.ini";
    config["DEFAULT"]["default_share_type"] = "tenant_share_type";
    config["DEFAULT"]["enabled_share_backends"] = "generic";
    config["DEFAULT"]["enabled_share_protocols"] = "NFS,CIFS";
    config["DEFAULT"]["rootwrap_config"] = "/etc/manila/rootwrap.conf";
    config["DEFAULT"]["share_name_template"] = "share-%s";

    config["oslo_concurrency"]["lock_path"] = "/var/lock/manila";
}

/**
 * Set the debug toggle.
 */
static void
SetDebug(Configs& config, const bool isDebug)
{
    config["DEFAULT"]["debug"] = isDebug ? "true" : "false";
}

/**
 * Set the endpoint of the process.
 */
static void
SetEndpoint(Configs& config, const std::string myIp)
{
    config["DEFAULT"]["my_ip"] = myIp;
    config["DEFAULT"]["osapi_share_listen"] = myIp;
}

/**
 * Set the connection to the database.
 */
static void
SetDatabaseConnection(
    Configs& config,
    const std::string sharedId,
    const std::string dbPass)
{
    std::stringstream uri;
    uri << "mysql+pymysql://manila:" << dbPass << "@" << sharedId << "/manila";

    config["database"]["connection"] = uri.str();
}

/**
 * Set the connection to the worker queue.
 */
static void
SetWorkerQueue(
    Configs& config,
    const bool isHa,
    const std::string sharedId,
    const std::string mqPass,
    const std::string ctrlAddrs)
{
    std::string dbconn = RabbitMqServers(isHa, sharedId, mqPass, ctrlAddrs);
    config["DEFAULT"]["transport_url"] = dbconn;
    config["DEFAULT"]["rpc_response_timeout"] = "1200";

    if (isHa) {
        config["oslo_messaging_rabbit"]["rabbit_retry_interval"] = "1";
        config["oslo_messaging_rabbit"]["rabbit_retry_backoff"] = "2";
        config["oslo_messaging_rabbit"]["amqp_durable_queues"] = "true";
        config["oslo_messaging_rabbit"]["rabbit_ha_queues"] = "true";
    }
}

/**
 * Set the connection to the notification queue.
 */
static void
SetNotificationQueue(
    Configs& config,
    const std::string sharedId)
{
    config["oslo_messaging_notifications"]["driver"] = "messagingv2";
    config["oslo_messaging_notifications"]["transport_url"] = std::string("kafka://") + sharedId + ":9095";
}
/**
 * Set the auth.
 */
static void
SetAuth(
    Configs& config,
    const std::string sharedId,
    const std::string domain,
    const std::string manilaPass)
{
    config["DEFAULT"]["auth_strategy"] = "keystone";

    config["keystone_authtoken"]["auth_type"] = "password";
    config["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";
    config["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
    config["keystone_authtoken"]["memcached_servers"] = sharedId + ":11211";
    config["keystone_authtoken"]["project_domain_name"] = domain;
    config["keystone_authtoken"]["project_name"] = "service";
    config["keystone_authtoken"]["user_domain_name"] = domain;
    config["keystone_authtoken"]["username"] = "manila";
    config["keystone_authtoken"]["password"] = manilaPass;
    config["keystone_authtoken"]["service_token_roles"] = "service";
    config["keystone_authtoken"]["service_token_roles_required"] = "true";
}

/**
 * Set the connection to Cinder.
 */
static void
SetCinderInfo(
    Configs& config,
    const std::string sharedId,
    const std::string region,
    const std::string domain,
    const std::string adminCliPass)
{
    config["cinder"]["auth_type"] = "password";
    config["cinder"]["auth_url"] = "http://" + sharedId + ":5000";
    config["cinder"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
    config["cinder"]["memcached_servers"] = sharedId + ":11211";
    config["cinder"]["region_name"] = region;
    config["cinder"]["project_domain_name"] = domain;
    config["cinder"]["project_name"] = "admin";
    config["cinder"]["user_domain_name"] = domain;
    config["cinder"]["username"] = "admin_cli";
    config["cinder"]["password"] = adminCliPass;
}

/**
 * Set the connection to Nova.
 */
static void
SetNovaInfo(
    Configs& config,
    const std::string sharedId,
    const std::string region,
    const std::string domain,
    const std::string adminCliPass)
{
    config["nova"]["auth_type"] = "password";
    config["nova"]["auth_url"] = "http://" + sharedId + ":5000";
    config["nova"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
    config["nova"]["memcached_servers"] = sharedId + ":11211";
    config["nova"]["region_name"] = region;
    config["nova"]["project_domain_name"] = domain;
    config["nova"]["project_name"] = "admin";
    config["nova"]["user_domain_name"] = domain;
    config["nova"]["username"] = "admin_cli";
    config["nova"]["password"] = adminCliPass;
}

/**
 * Set the connection to Neutron.
 */
static void
SetNeutronInfo(
    Configs& config,
    const std::string sharedId,
    const std::string region,
    const std::string domain,
    const std::string adminCliPass)
{
    config["neutron"]["auth_type"] = "password";
    config["neutron"]["auth_url"] = "http://" + sharedId + ":5000";
    config["neutron"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
    config["neutron"]["memcached_servers"] = sharedId + ":11211";
    config["neutron"]["region_name"] = region;
    config["neutron"]["project_domain_name"] = domain;
    config["neutron"]["project_name"] = "admin";
    config["neutron"]["user_domain_name"] = domain;
    config["neutron"]["username"] = "admin_cli";
    config["neutron"]["password"] = adminCliPass;
    config["neutron"]["url"] = "http://" + sharedId + ":9696";
}

/**
 * Set the connection to Glance.
 */
static void
SetGlanceInfo(
    Configs& config,
    const std::string sharedId,
    const std::string region,
    const std::string domain,
    const std::string adminCliPass)
{
    config["glance"]["auth_type"] = "password";
    config["glance"]["auth_url"] = "http://" + sharedId + ":5000";
    config["glance"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
    config["glance"]["memcached_servers"] = sharedId + ":11211";
    config["glance"]["region_name"] = region;
    config["glance"]["project_domain_name"] = domain;
    config["glance"]["project_name"] = "admin";
    config["glance"]["user_domain_name"] = domain;
    config["glance"]["username"] = "admin_cli";
    config["glance"]["password"] = adminCliPass;
}

/**
 * Set the generic driver.
 */
static void
SetDriverGeneric(
    Configs& config,
    const std::string networkCidr,
    const std::string volumeType)
{
    config["generic"]["share_backend_name"] = "GENERIC";
    config["generic"]["share_driver"] = "manila.share.drivers.generic.GenericShareDriver";
    config["generic"]["driver_handles_share_servers"] = "true";
    config["generic"]["interface_driver"] = "manila.network.linux.interface.OVSInterfaceDriver";
    config["generic"]["connect_share_server_to_tenant_network"] = "true";
    config["generic"]["service_image_name"] = "manila-service-image";
    config["generic"]["service_instance_flavor_id"] = "653443";
    config["generic"]["service_instance_user"] = "manila";
    config["generic"]["service_instance_password"] = "manila";

    config["generic"]["service_network_cidr"] = networkCidr;
    int mask = std::stoi(hex_string_util::split(networkCidr, '/')[1]) + 7;
    mask = std::min(mask, 32);
    config["generic"]["service_network_division_mask"] = std::to_string(mask);

    config["generic"]["cinder_volume_type"] = volumeType;
}

/**
 * Set up Manila service.
 * The function should be run after Keystone service is running.
 */
static void
SetupService(const std::string domain, const std::string userPass)
{
    HexLogInfo("Setting up manila");

    // populate the database for manila service
    HexUtilSystemF(
        0,
        0,
        "su -s /bin/sh -c \"manila-manage db sync\" %s",
        USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // create the manila service credentials
    HexUtilSystemF(
        0,
        0,
        "%s %s user create --domain %s --password %s %s",
        env.c_str(),
        OSCMD,
        domain.c_str(),
        userPass.c_str(),
        USER);
    HexUtilSystemF(
        0,
        0,
        "%s %s role add --project service --user %s admin",
        env.c_str(),
        OSCMD,
        USER);

    // create the service entity
    HexUtilSystemF(
        0,
        0,
        "%s %s service create --name manila --description \"OpenStack Shared File Systems\" share",
        env.c_str(),
        OSCMD);
    HexUtilSystemF(
        0,
        0,
        "%s %s service create --name manilav2 --description \"OpenStack Shared File Systems\" sharev2",
        env.c_str(),
        OSCMD);
}
/**
 * Set service endpoints.
 */
static void
SetServiceEndpoints(
    const std::string endpoint,
    const std::string external,
    const std::string region)
{
    HexLogInfo("Updating manila endpoint");

    const std::string publicUrlV1 = "http://" + external + ":8786/v1/%\\(tenant_id\\)s";
    const std::string adminUrlV1 = "http://" + endpoint + ":8786/v1/%\\(tenant_id\\)s";
    const std::string internalUrlV1 = "http://" + endpoint + ":8786/v1/%\\(tenant_id\\)s";

    HexUtilSystemF(
        0,
        0,
        "%s os_endpoint_update %s %s %s %s %s",
        HEX_SDK,
        "share",
        region.c_str(),
        publicUrlV1.c_str(),
        adminUrlV1.c_str(),
        internalUrlV1.c_str());

    const std::string publicUrlV2 = "http://" + external + ":8786/v2/%\\(tenant_id\\)s";
    const std::string adminUrlV2 = "http://" + endpoint + ":8786/v2/%\\(tenant_id\\)s";
    const std::string internalUrlV2 = "http://" + endpoint + ":8786/v2/%\\(tenant_id\\)s";

    HexUtilSystemF(
        0,
        0,
        "%s os_endpoint_update %s %s %s %s %s",
        HEX_SDK,
        "sharev2",
        region.c_str(),
        publicUrlV2.c_str(),
        adminUrlV2.c_str(),
        internalUrlV2.c_str());
}

/**
 * Start Manila services.
 */
static void
StartManilaService(const bool enabled)
{
    if (IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled, API_NAME);
        SystemdCommitService(enabled, SCHEDULER_NAME);
    }

    if (IsCompute(s_eCubeRole)) {
        SystemdCommitService(enabled, SHARE_NAME);
    }
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    // we only run Manila services on control and compute nodes
    if (!(IsControl(s_eCubeRole) || IsCompute(s_eCubeRole))
        || !CommitCheck(modified, dryLevel)) {
        return true;
    }

    std::string myip = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    std::string mgmtCidr = GetMgmtCidr(s_mgmtCidr.newValue(), 1);
    std::string manilaPass = GetSaltKey(s_saltkey, s_manilaPass.newValue(), s_seed.newValue());
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass.newValue(), s_seed.newValue());
    std::string adminCliPass = GetSaltKey(s_saltkey, s_adminCliPass.newValue(), s_seed.newValue());

    if (IsControl(s_eCubeRole)) {
        // set up the database
        if (!IsDatabaseSetup()) {
            s_bSetup = false;
            SetupDatabase();
        }

        if (!s_bSetup) {
            s_bDbPassChanged = true;
            s_bEndpointChanged = true;
        }

        // configure the database
        if (s_bDbPassChanged) {
            MysqlUtilUpdateDbPass(USER, dbPass.c_str());
        }
    }

    // update config file
    if (s_bConfigChanged) {
        LoadDefaultConfig(config);
        InitConfig(config);
        SetDefaults(config);
        SetDebug(config, s_debug);
        SetEndpoint(config, myip);
        SetDatabaseConnection(config, sharedId, dbPass);
        SetWorkerQueue(config, s_ha, sharedId, mqPass, s_ctrlAddrs);
        SetNotificationQueue(config, sharedId);
        SetAuth(config, sharedId, s_cubeDomain, manilaPass);
        SetCinderInfo(config, sharedId, s_cubeRegion, s_cubeDomain, adminCliPass);
        SetNovaInfo(config, sharedId, s_cubeRegion, s_cubeDomain, adminCliPass);
        SetNeutronInfo(config, sharedId, s_cubeRegion, s_cubeDomain, adminCliPass);
        SetGlanceInfo(config, sharedId, s_cubeRegion, s_cubeDomain, adminCliPass);

        if (s_volumeType.length() > 0 && s_volumeType.newValue() != BUILTIN_VOLUME_TYPE) {
            SetDriverGeneric(config, mgmtCidr, s_volumeType);
        } else if (s_cinderVolumeTypeDefault.newValue() != "") {
            SetDriverGeneric(config, mgmtCidr, s_cinderVolumeTypeDefault);
        } else {
            SetDriverGeneric(config, mgmtCidr, BUILTIN_VOLUME_TYPE);
        }

        WriteConfig(CONF, SB_SEC_WFMT, '=', config);
    }

    if (IsControl(s_eCubeRole)) {
        // set up the service
        if (!s_bSetup) {
            SetupService(s_cubeDomain, manilaPass);
        }

        // check for db migration
        HexUtilSystemF(0, 0, HEX_SDK " migrate_manila_db");

        // set service endpoints
        if (s_bEndpointChanged) {
            SetServiceEndpoints(sharedId, external, s_cubeRegion);
        }
    }

    // start services
    StartManilaService(s_enabled);

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_manila\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    StartManilaService(s_enabled);

    return EXIT_SUCCESS;
}

/**
 * Check if Manila is initiated cluster wise.
 */
static bool
IsInit()
{
    if (!IsControl(s_eCubeRole))
        return true;

    return access(INIT_DONE, F_OK) == 0;
}

static int
ClusterStartMain(int argc, char** argv)
{
    if (argc != 1)
        return EXIT_FAILURE;

    bool enabled = s_enabled;
    if (!enabled)
        return EXIT_SUCCESS;

    if (IsControl(s_eCubeRole)) {
        if (!IsInit()) {
            HexUtilSystemF(0, 0, HEX_SDK " os_manila_init");
            HexSystemF(0, "touch " INIT_DONE);
        }

        // post actions for db migration
        HexUtilSystemF(0, 0, HEX_SDK " migrate_manila_db_post");
    }

    return EXIT_SUCCESS;
}

CONFIG_MODULE(manila, Init, Parse, 0, 0, Commit);
// startup sequence
CONFIG_REQUIRES(manila, memcache);
CONFIG_REQUIRES(manila, neutron);
CONFIG_REQUIRES(manila, nova);
CONFIG_REQUIRES(manila, cinder);

// extra tunings
CONFIG_OBSERVES(manila, rabbitmq, ParseRabbitMQ, NotifyMQ);
CONFIG_OBSERVES(manila, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(manila, keystone, ParseKeystone, NotifyKeystone);
CONFIG_OBSERVES(manila, cinder, ParseCinder, NotifyCinder);

CONFIG_TRIGGER_WITH_SETTINGS(manila, "cluster_start", ClusterStartMain);

CONFIG_COMMAND_WITH_SETTINGS(restart_manila, RestartMain, RestartUsage);
