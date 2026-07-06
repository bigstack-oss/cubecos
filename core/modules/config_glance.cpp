// CUBE SDK

#include "include/role_cubesys.h"
#include "mysql_util.h"
#include <cluster.hpp>
#include <constant.hpp>
#include <cube/config_file.h>
#include <cube/systemd_util.h>
#include <fcntl.h>
#include <hex/config_global.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/dryrun.h>
#include <hex/filesystem.h>
#include <hex/log.h>
#include <hex/logrotate.h>
#include <hex/pidfile.h>
#include <hex/process.h>
#include <hex/process_util.h>

static LogRotateConf log_conf("glance", "/var/log/glance/*.log", DAILY, 128, 0, true);

static const char USER[] = "glance";
static const char GROUP[] = "glance";
static const char VOLUME[] = "glance-images";

// glance config files
#define GA_CONF "/etc/glance/glance-api.conf"

static const char GA_NAME[] = "openstack-glance-api";

static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char USERPASS[] = "0ZsvkS1bHXYsywTx";
static const char DBPASS[] = "g6CEJCNFT6ufPY22";

static const char EXPORT_SYNC[] = "/etc/cron.d/glance_export_sync";
static const char TwoTiB[] = "2199023255552";

#define BUILTIN_STORE "cube"

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(GLANCE_ENABLED, "glance.enabled", TUNING_UNPUB, "Set to true to enable glance.", true);
CONFIG_TUNING_STR(GLANCE_USERPASS, "glance.user.password", TUNING_UNPUB, "Set glance user password.", USERPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(GLANCE_DBPASS, "glance.db.password", TUNING_UNPUB, "Set glance database password.", DBPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_BOOL(GLANCE_CINDER_USE_MULTIPATH, "glance.cinder.useMultipath", TUNING_UNPUB, "Use multipath for volume-backed images.", true);
CONFIG_TUNING_BOOL(GLANCE_CINDER_ENFORCE_MULTIPATH, "glance.cinder.enforceMultipath", TUNING_UNPUB, "Enforce multipath for volume-backed images.", true);

// public tunigns
CONFIG_TUNING_BOOL(GLANCE_DEBUG, "glance.debug.enabled", TUNING_PUB, "Set to true to enable glance verbose log.", false);
CONFIG_TUNING_INT(GLANCE_EXPORT_RP, "glance.export.rp", TUNING_PUB, "glance export retention policy in copies.", 3, 0, 255);

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_REGION);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_STR(RABBITMQ_OPENSTACK_PASSWD);
CONFIG_TUNING_SPEC_STR(CINDER_STORAGE_BACKEND);
CONFIG_TUNING_SPEC_STR(CINDER_VOLUME_TYPE_DEFAULT);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, GLANCE_ENABLED);
PARSE_TUNING_STR(s_glancePass, GLANCE_USERPASS);
PARSE_TUNING_STR(s_dbPass, GLANCE_DBPASS);
PARSE_TUNING_INT(s_exportRp, GLANCE_EXPORT_RP);
PARSE_TUNING_BOOL(s_cinderUseMultipath, GLANCE_CINDER_USE_MULTIPATH);
PARSE_TUNING_BOOL(s_cinderEnforceMultipath, GLANCE_CINDER_ENFORCE_MULTIPATH);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 1);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);
PARSE_TUNING_X_STR(s_mqPass, RABBITMQ_OPENSTACK_PASSWD, 2);
PARSE_TUNING_X_STR_ARRAY(s_storageBackends, CINDER_STORAGE_BACKEND, 3);
PARSE_TUNING_X_STR(s_volumeTypeDefault, CINDER_VOLUME_TYPE_DEFAULT, 3);

static bool s_bSetup = true;
static bool s_bCubeModified = false;
static bool s_bMqModified = false;
static bool s_bCinderModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bEndpointChanged = false;

static CubeRole_e s_eCubeRole;
static Configs config;

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
ParseRabbitMQ(const char* name, const char* value, bool isNew)
{
    ParseTune(name, value, isNew, 2);
    return true;
}

static void
NotifyMQ(bool modified)
{
    s_bMqModified = IsModifiedTune(2);
}

static bool
ParseCinder(const char* name, const char* value, bool isNew)
{
    ParseTune(name, value, isNew, 3);
    return true;
}

static void
NotifyCinder(bool modified)
{
    s_bCinderModified = IsModifiedTune(3);
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
        || s_bCinderModified
        || s_bMqModified
        || s_bCubeModified
        || G_MOD(MGMT_ADDR)
        || G_MOD(SHARED_ID);

    s_bEndpointChanged = s_bCubeModified
        || G_MOD(SHARED_ID)
        || G_MOD(EXTERNAL);

    return s_bDbPassChanged || s_bConfigChanged || s_bEndpointChanged;
}

/**
 * Check if the database is set up for Glance.
 */
static bool
IsDatabaseSetup()
{
    return MysqlUtilIsDbExist("glance");
}

/**
 * Set up the database for Glance.
 */
static bool
SetupDatabase()
{
    if (IsDatabaseSetup()) {
        return true;
    }

    if (!MysqlUtilRunSQL("CREATE DATABASE glance")
        || !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'glance_dbpass'")
        || !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'glance_dbpass'")) {
        return false;
    }

    return true;
}

/**
 * Set up the Ceph RBD pool for the built-in Glance store.
 */
static void
SetupRbdPools()
{
    // create the pool for glance store
    HexUtilSystemF(0, 0, HEX_SDK " ceph_create_pool %s rbd", VOLUME);
    HexUtilSystemF(0, 0, "timeout 10 ceph osd pool set %s bulk true", VOLUME);
}

/**
 * Set up the cron job to clean up the glance directory in CephFS.
 */
static bool
SetupGlanceExportSyncCronJob(const int rp)
{
    int fd = open(EXPORT_SYNC, O_CREAT | O_WRONLY | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
    if (fd == -1) {
        HexLogError("Unable to open file %s", EXPORT_SYNC);
        return false;
    }
    FILE* fout = fdopen(fd, "w");
    if (!fout) {
        HexLogError("Unable to write %s export sync-er: %s", USER, EXPORT_SYNC);
        return false;
    }

    fprintf(fout, "*/5 * * * * root " HEX_SDK " os_glance_export_sync %d\n", rp);
    fclose(fout);

    if (HexSetFileMode(EXPORT_SYNC, "root", "root", 0644) != 0) {
        HexLogError("Unable to set file %s mode/permission", EXPORT_SYNC);
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
    if (!LoadConfig(GA_CONF DEF_EXT, SB_SEC_RFMT, '=', config)) {
        HexLogError("Failed to load the default glance api config file %s", GA_CONF DEF_EXT);
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
        "barbican",
        "barbican_service_user",
        "cinder",
        "cors",
        "database",
        "file",
        "glance.store.http.store",
        "glance.store.rbd.store",
        "glance.store.s3.store",
        "glance.store.swift.store",
        "glance.store.vmware_datastore.store",
        "glance_store",
        "healthcheck",
        "image_format",
        "key_manager",
        "keystone_authtoken",
        "oslo_concurrency",
        "oslo_messaging_amqp",
        "oslo_messaging_kafka",
        "oslo_messaging_notifications",
        "oslo_messaging_rabbit",
        "oslo_middleware",
        "oslo_policy",
        "oslo_reports",
        "paste_deploy",
        "profiler",
        "store_type_location_strategy",
        "task",
        "taskflow_executor",
        "vault",
        "wsgi",
    };

    SetupConfig(sections, config);
}

/**
 * Set the defaults.
 */
static void
SetDefaults(Configs& config)
{
    config["DEFAULT"]["show_image_direct_url"] = "true";
    config["DEFAULT"]["show_multiple_locations"] = "true";
    config["DEFAULT"]["workers"] = std::to_string(GetControlWorkers(IsConverged(s_eCubeRole), IsEdge(s_eCubeRole)));
    config["DEFAULT"]["image_size_cap"] = TwoTiB;
    config["DEFAULT"]["node_staging_uri"] = "file:///mnt/cephfs/glance_tmp_transition";

    config["oslo_concurrency"]["lock_path"] = "/var/lib/glance/locks";

    // should be oslo_reports.log_dir, however, the current version does not support it
    config["DEFAULT"]["log_dir"] = "/var/log/glance";

    config["paste_deploy"]["flavor"] = "keystone";
    config["paste_deploy"]["config_file"] = "/etc/glance/glance-api-paste.ini";
}

/**
 * Set the endpoint of the process.
 */
static void
SetEndpoint(Configs& config, const std::string myIp)
{
    config["DEFAULT"]["bind_host"] = myIp;
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
    uri << "mysql+pymysql://glance:" << dbPass << "@" << sharedId << "/glance";

    config["database"]["connection"] = uri.str();
    config["database"]["mysql_wsrep_sync_wait"] = "1";
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
    const std::string glancePass)
{
    config["keystone_authtoken"]["auth_type"] = "password";
    config["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";
    config["keystone_authtoken"]["http_connect_timeout"] = "15";
    config["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
    config["keystone_authtoken"]["memcached_servers "] = sharedId + ":11211";
    config["keystone_authtoken"]["project_domain_name"] = domain;
    config["keystone_authtoken"]["project_name"] = "service";
    config["keystone_authtoken"]["user_domain_name"] = domain;
    config["keystone_authtoken"]["username"] = "glance";
    config["keystone_authtoken"]["password"] = glancePass;
    config["keystone_authtoken"]["service_token_roles"] = "service";
    config["keystone_authtoken"]["service_token_roles_required"] = "false";
}

/**
 * Set Cinder store defaults.
 */
static void
SetCinderInfo(
    Configs& config,
    const bool useMultipath,
    const bool enforceMultipath)
{
    config["cinder"]["cinder_use_multipath"] = useMultipath ? "true" : "false";
    config["cinder"]["cinder_enforce_multipath"] = enforceMultipath ? "true" : "false";
    config["cinder"]["cinder_state_transition_timeout"] = "1200";
}

/**
 * Set store http:http.
 */
static void
SetHttpStore(Configs& config)
{
    config.emplace("http", ConfigList {});
    config["http"]["store_description"] = "\"http\"";
}

/**
 * Set the built-in store cube:rbd.
 */
static void
SetCubeStore(Configs& config)
{
    config.emplace(BUILTIN_STORE, ConfigList {});
    config[BUILTIN_STORE]["store_description"] = "\"Built-in Ceph RBD\"";
    config[BUILTIN_STORE]["rbd_store_ceph_conf"] = "/etc/ceph/ceph.conf";
    config[BUILTIN_STORE]["rbd_store_chunk_size"] = "8";
    config[BUILTIN_STORE]["rbd_store_pool"] = VOLUME;
    config[BUILTIN_STORE]["rbd_store_user"] = USER;
}

/**
 * Set Cinder volume-backed stores.
 */
static void
SetCinderStores(
    Configs& config,
    const std::vector<std::string>& cinderStores,
    const std::string sharedId,
    const std::string glancePass)
{
    for (std::vector<std::string>::const_iterator it = cinderStores.begin(); it != cinderStores.end(); it++) {
        // filter out the empty strings
        if ((*it).empty()) {
            continue;
        }

        std::string volumeType = *it;
        config.emplace(volumeType, ConfigList {});
        config[volumeType]["store_description"] = "\"Cinder volume type " + volumeType + "\"";
        config[volumeType]["cinder_store_auth_address"] = "http://" + sharedId + ":5000";
        config[volumeType]["cinder_store_user_name"] = "glance";
        config[volumeType]["cinder_store_password"] = glancePass;
        config[volumeType]["cinder_store_project_name"] = "service";
        config[volumeType]["cinder_volume_type"] = volumeType;
    }
}

/**
 * Set stores.
 */
static void
SetStores(
    Configs& config,
    const std::vector<std::string>& cinderStores)
{
    // enabled store
    std::stringstream stores;
    stores << "http:http" << "," << BUILTIN_STORE << ":rbd";
    for (std::vector<std::string>::const_iterator it = cinderStores.begin(); it != cinderStores.end(); it++) {
        // filter out the empty strings
        if ((*it).empty()) {
            continue;
        }

        stores << "," << *it << ":cinder";
    }
    config["DEFAULT"]["enabled_backends"] = stores.str();
}

/**
 * Set the default store.
 */
static void
SetDefaultStore(
    Configs& config,
    const std::string defaultVolumeType)
{
    // default store
    if (defaultVolumeType.length() == 0 || defaultVolumeType == BUILTIN_VOLUME_TYPE) {
        /**
         * If built-ins are in use,
         * set Glance to use its own built-in,
         * glance-images Ceph RBD pool, instead.
         */
        config["glance_store"]["default_backend"] = BUILTIN_STORE;
    } else {
        config["glance_store"]["default_backend"] = defaultVolumeType;
    }
}

/**
 * Set up Glance service.
 * The function should be run after Keystone service is running.
 */
static void
SetupService(const std::string domain, const std::string userPass)
{
    HexLogInfo("Setting up glance");

    // populate the glance service database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"glance-manage db_sync\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // create the glance service credentials
    HexUtilSystemF(
        0,
        0,
        "%s %s user create --domain %s --password %s glance",
        env.c_str(),
        OPENSTACK_CLI,
        domain.c_str(),
        userPass.c_str());
    HexUtilSystemF(
        0,
        0,
        "%s %s role add --project service --user glance admin",
        env.c_str(),
        OPENSTACK_CLI);

    // create the service entity
    HexUtilSystemF(
        0,
        0,
        "%s %s service create --name %s --description \"OpenStack Image\" image",
        env.c_str(),
        OPENSTACK_CLI,
        USER);
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
    HexLogInfo("Updating glance endpoint");

    const std::string publicUrl = "http://" + external + ":9292";
    const std::string adminUrl = "http://" + endpoint + ":9292";
    const std::string internalUrl = "http://" + endpoint + ":9292";

    HexUtilSystemF(
        0,
        0,
        "%s os_endpoint_update %s %s %s %s %s",
        HEX_SDK,
        "image",
        region.c_str(),
        publicUrl.c_str(),
        adminUrl.c_str(),
        internalUrl.c_str());
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    // we only run Glance services on control nodes
    if (!IsControl(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    std::string myIp = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    std::string glancePass = GetSaltKey(s_saltkey, s_glancePass.newValue(), s_seed.newValue());
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass.newValue(), s_seed.newValue());

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

    // set up the Ceph RBD pools
    if (!s_bSetup) {
        SetupRbdPools();
    }

    // set up the cron job to clean up the glance directory in CephFS
    if (s_bConfigChanged) {
        SetupGlanceExportSyncCronJob(s_exportRp);
    }

    // configure the services
    if (s_bConfigChanged) {
        LoadDefaultConfig(config);
        InitConfig(config);
        SetDefaults(config);
        SetEndpoint(config, myIp);
        SetDatabaseConnection(config, sharedId, dbPass);
        SetWorkerQueue(config, s_ha, sharedId, mqPass, s_ctrlAddrs);
        SetNotificationQueue(config, sharedId);
        SetAuth(config, sharedId, s_cubeDomain, glancePass);
        SetCinderInfo(config, s_cinderUseMultipath, s_cinderEnforceMultipath);
        SetHttpStore(config);
        SetCubeStore(config);

        std::vector<std::string> cinderStores;
        for (std::vector<ConfigString>::const_iterator it = s_storageBackends.begin(); it != s_storageBackends.end(); it++) {
            // filter out the empty strings
            if ((*it).empty()) {
                continue;
            }
            cinderStores.push_back(*it);
        }
        SetCinderStores(config, cinderStores, sharedId, glancePass);
        SetStores(config, cinderStores);
        if (s_volumeTypeDefault.newValue() != "") {
            SetDefaultStore(config, s_volumeTypeDefault);
        } else {
            SetDefaultStore(config, BUILTIN_VOLUME_TYPE);
        }

        // write to glance config files
        WriteConfig(GA_CONF, SB_SEC_WFMT, '=', config);
    }

    // set up the service
    if (!s_bSetup) {
        SetupService(s_cubeDomain, glancePass);
    }

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_glance_db");

    // set service endpoints
    if (s_bEndpointChanged) {
        SetServiceEndpoints(sharedId, external, s_cubeRegion);
    }

    // start services
    SystemdCommitService(s_enabled, GA_NAME, true);
    WriteLogRotateConf(log_conf);

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_glance\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    if (!IsControl(s_eCubeRole)) {
        return EXIT_SUCCESS;
    }
    SystemdCommitService(s_enabled, GA_NAME, true);

    return EXIT_SUCCESS;
}

CONFIG_MODULE(glance, 0, Parse, 0, 0, Commit);
// startup sequence
CONFIG_REQUIRES(glance, keystone);
CONFIG_REQUIRES(glance, memcache);
CONFIG_REQUIRES(glance, cinder);
CONFIG_REQUIRES(glance, ceph);
// extra tunings
CONFIG_OBSERVES(glance, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(glance, rabbitmq, ParseRabbitMQ, NotifyMQ);
CONFIG_OBSERVES(glance, cinder, ParseCinder, NotifyCinder);

CONFIG_COMMAND_WITH_SETTINGS(restart_glance, RestartMain, RestartUsage);

static bool
liftQuotaForVolumeImage()
{
    HexLogInfo("glance: lift quota for volume image");
    ExecSyncResult r = ExecBashSync(
        0,
        false,
        false,
        {},
        std::string(HEX_SDK) + " glance_lift_quota_for_volume_image");
    if (r.exitCode != 0) {
        HexLogError("glance: failed to lift quota for volume image");
        return false;
    }

    HexLogInfo("glance: lifted quota for volume image");
    return true;
}

static int
ClusterStartMain(int argc, char** argv)
{
    if (argc != 1) {
        return EXIT_FAILURE;
    }

    liftQuotaForVolumeImage();

    return EXIT_SUCCESS;
}

CONFIG_TRIGGER(glance, "cluster_start", ClusterStartMain);
