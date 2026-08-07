// CUBE SDK

#include "include/role_cubesys.h"

#include <cluster.hpp>
#include <constant.hpp>
#include <cube/config_file.h>
#include <cube/systemd_util.h>
#include <filesystem.hpp>
#include <hex/config_global.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/dryrun.h>
#include <hex/exec.hpp>
#include <hex/filesystem.h>
#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <mysql_util.h>

static const char USER[] = "cinder";
static const char GROUP[] = "cinder";
static const char VOLUME[] = "cinder-volumes";
static const char BACKUP[] = "volume-backups";

/**
 * Cinder config file.
 */
#define CONF "/etc/cinder/cinder.conf"
/**
 * Cinder config directory.
 */
#define CONF_DIR "/etc/cinder/cinder.d"
/**
 * Marker file stating that Ceph pools are ready for Cinder
 */
#define MAKRER_POOL "/etc/appliance/state/cinder_pool_done"

// cinder common
static const char RUNDIR[] = "/run/cinder";
static const char STATDIR[] = "/store/cinder";

/**
 * cinder-api
 */
static const char API_NAME[] = "openstack-cinder-api";
/**
 * cinder-scheduler
 */
static const char SCHL_NAME[] = "openstack-cinder-scheduler";
/**
 * cinder-volume
 */
static const char VOL_NAME[] = "openstack-cinder-volume";
/**
 * cinder-backup
 */
static const char BAK_NAME[] = "openstack-cinder-backup";

static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char USERPASS[] = "8YHpMKC1394HbTmL";
static const char DBPASS[] = "hhyCDG3IdNmcQaJo";

#define BUILTIN_STORAGE_BACKEND "ceph"
#define BUILTIN_STORAGE_HOST "cube"

// external global variables
CONFIG_GLOBAL_STR_REF(CTRL_IP);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);
CONFIG_GLOBAL_BOOL_REF(IS_MASTER);

// private tunings
CONFIG_TUNING_BOOL(CINDER_ENABLED, "cinder.enabled", TUNING_UNPUB, "Set to true to enable cinder.", true);
CONFIG_TUNING_STR(CINDER_USERPASS, "cinder.user.password", TUNING_UNPUB, "Set cinder user password.", USERPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_DBPASS, "cinder.db.password", TUNING_UNPUB, "Set cinder database password.", DBPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_STORAGE_BACKEND, "cinder.storage.backend.%d.name", TUNING_UNPUB, "Set additional storage backends.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_VOLUME_TYPE_DEFAULT, "cinder.storage.volumeType.default", TUNING_UNPUB, "Set the default cinder volume type.", BUILTIN_VOLUME_TYPE, ValidateRegex, DFT_REGEX_STR);

// public tunigns
CONFIG_TUNING_BOOL(CINDER_DEBUG, "cinder.debug.enabled", TUNING_PUB, "Set to true to enable cinder verbose log.", false);
CONFIG_TUNING_BOOL(CINDER_BACKUP_OVERRIDE, "cinder.backup.override", TUNING_PUB, "Enable override cinder backup configurations.", false);
CONFIG_TUNING_STR(CINDER_BACKUP_TYPE, "cinder.backup.type", TUNING_PUB, "Set cinder backup storage type <cube-storage|cube-swift>.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_BACKUP_ENDPOINT, "cinder.backup.endpoint", TUNING_PUB, "Set cinder backup storage endpoint.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_BACKUP_ACCOUNT, "cinder.backup.account", TUNING_PUB, "Set cinder backup storage account.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_BACKUP_SECRET, "cinder.backup.secret", TUNING_PUB, "Set cinder backup storage account secret.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_BACKUP_POOL, "cinder.backup.pool", TUNING_PUB, "Set cinder backup storage pool.", "", ValidateRegex, DFT_REGEX_STR);

// using external tunings
CONFIG_TUNING_SPEC_STR(RABBITMQ_OPENSTACK_PASSWD);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_REGION);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_STR(NOVA_USERPASS);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, CINDER_ENABLED);
PARSE_TUNING_BOOL(s_debug, CINDER_DEBUG);
PARSE_TUNING_STR(s_cinderPass, CINDER_USERPASS);
PARSE_TUNING_STR(s_dbPass, CINDER_DBPASS);
PARSE_TUNING_STR_ARRAY(s_storageBackends, CINDER_STORAGE_BACKEND);
PARSE_TUNING_STR(s_volumeTypeDefault, CINDER_VOLUME_TYPE_DEFAULT);
PARSE_TUNING_BOOL(s_backupOverride, CINDER_BACKUP_OVERRIDE);
PARSE_TUNING_STR(s_backupType, CINDER_BACKUP_TYPE);
PARSE_TUNING_STR(s_backupEndpoint, CINDER_BACKUP_ENDPOINT);
PARSE_TUNING_STR(s_backupAccount, CINDER_BACKUP_ACCOUNT);
PARSE_TUNING_STR(s_backupSecret, CINDER_BACKUP_SECRET);
PARSE_TUNING_STR(s_backupPool, CINDER_BACKUP_POOL);
PARSE_TUNING_X_STR(s_mqPass, RABBITMQ_OPENSTACK_PASSWD, 1);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 2);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 2);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 2);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 2);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 2);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 2);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 2);
PARSE_TUNING_X_STR(s_novaPass, NOVA_USERPASS, 3);

static bool s_bSetup = true;

static bool s_bMqModified = false;
static bool s_bCubeModified = false;
static bool s_bNovaModified = false;

static bool s_bDbPassChanged = false;
static bool s_bEndpointChanged = false;
static bool s_bConfigChanged = false;
static bool s_bStorageBackendChanged = false;

static CubeRole_e s_eCubeRole;
static Configs mainConfig;

static bool
ParseRabbitMQ(const char* name, const char* value, bool isNew)
{
    ParseTune(name, value, isNew, 1);
    return true;
}

static void
NotifyRabbitMQ(bool modified)
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
ParseNova(const char* name, const char* value, bool isNew)
{
    ParseTune(name, value, isNew, 3);
    return true;
}

static void
NotifyNova(bool modified)
{
    s_bNovaModified = s_novaPass.modified();
}

static bool
Init()
{
    if (HexMakeDir(RUNDIR, USER, GROUP, 0755) != 0 || HexMakeDir(CINDER_BACKEND_DIR, USER, GROUP, 0755) != 0)
        return false;

    // fail safe for creating state dir
    HexMakeDir(STATDIR, USER, GROUP, 0755);

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

/**
 * Check if storage backend configs are modified.
 *
 * Since we write storage configs in hex_sdk instead of setting them as tunings,
 * hex_config could not detect the changes directly from tunings.
 * We would need to perform the checks ourselves.
 *
 * @return is storage backend config files modified or not
 */
static bool
isStorageBackendModified()
{
    std::string fsError;
    const std::vector<std::string> configuredConfigs = GetFilesUnderDirectory(fsError, CINDER_BACKEND_DIR);
    if (!fsError.empty()) {
        HexLogError("%s", fsError.c_str());
        return false;
    }
    const std::vector<std::string> currentConfigs = GetFilesUnderDirectory(fsError, CONF_DIR);
    if (!fsError.empty()) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    // first check the length, if not even, then must be modified
    if (configuredConfigs.size() != currentConfigs.size()) {
        return true;
    }

    // then check the names are the same set or not
    for (const std::string& con : configuredConfigs) {
        bool fileFound = false;
        for (const std::string& cur : currentConfigs) {
            if (std::filesystem::path(con).filename().string() == std::filesystem::path(cur).filename().string()) {
                fileFound = true;
                break;
            }
        }

        if (!fileFound) {
            return true;
        }
    }
    for (const std::string& cur : currentConfigs) {
        bool fileFound = false;
        for (const std::string& con : configuredConfigs) {
            if (std::filesystem::path(con).filename().string() == std::filesystem::path(cur).filename().string()) {
                fileFound = true;
                break;
            }
        }

        if (!fileFound) {
            return true;
        }
    }

    // check file modification times
    for (const std::string& p : configuredConfigs) {
        const std::filesystem::path configuredConfigFile(p);

        const std::string fileName = std::filesystem::path(p).filename();
        const std::filesystem::path currentConfigFile = std::filesystem::path(CONF_DIR) / fileName;

        // if the current correspondence does not exist, then must be modified
        if (!std::filesystem::exists(currentConfigFile)
            || !std::filesystem::is_regular_file(currentConfigFile)) {
            return true;
        }

        if (std::filesystem::last_write_time(configuredConfigFile)
            > std::filesystem::last_write_time(currentConfigFile)) {
            return true;
        }
    }

    return false;
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

    s_bStorageBackendChanged = s_storageBackends.modified()
        || s_volumeTypeDefault.modified()
        || isStorageBackendModified();

    s_bConfigChanged = modified
        || s_bMqModified
        || s_bCubeModified
        || s_bNovaModified
        || s_bStorageBackendChanged
        || G_MOD(CTRL_IP)
        || G_MOD(SHARED_ID);

    s_bEndpointChanged = s_bCubeModified
        || G_MOD(SHARED_ID)
        || G_MOD(EXTERNAL);

    return s_bDbPassChanged
        || s_bConfigChanged
        || s_bEndpointChanged
        || s_bStorageBackendChanged;
}

/**
 * Check if the database is set up for Cinder.
 */
static bool
IsDatabaseSetup()
{
    return MysqlUtilIsDbExist("cinder");
}

/**
 * Set up the database for Cinder.
 * Return:
 * - true: The database has been successfully set up.
 * - false: The database is failed to be set up.
 */
static bool
SetupDatabase()
{
    if (IsDatabaseSetup()) {
        return true;
    }

    if (!MysqlUtilRunSQL("CREATE DATABASE cinder")
        || !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY 'cinder_dbpass'")
        || !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY 'cinder_dbpass'")) {
        return false;
    }

    return true;
}

/**
 * Set up the Ceph RBD pool for the built-in Cinder volume and backup service.
 */
static void
SetupRbdPools()
{
    if (access(MAKRER_POOL, F_OK) != 0) {
        // create the cinder volume/backup storage
        HexUtilSystemF(0, 0, HEX_SDK " ceph_create_pool %s rbd", VOLUME);
        HexUtilSystemF(0, 0, HEX_SDK " ceph_create_pool %s rbd", BACKUP);
        HexUtilSystemF(0, 0, "timeout 10 ceph osd pool set %s bulk true", VOLUME);

        HexSystemF(0, "touch " MAKRER_POOL);
    }
}

/**
 * Load default configs.
 */
static bool
LoadDefaultConfig(Configs& config)
{
    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', config)) {
        HexLogError("Failed to load the default cinder config file %s", CONF DEF_EXT);
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
        "backend",
        "backend_defaults",
        "barbican",
        "barbican_service_user",
        "brcd_fabric_example",
        BUILTIN_STORAGE_BACKEND,
        "cisco_fabric_example",
        "coordination",
        "cors",
        "database",
        "fc-zone-manager",
        "healthcheck",
        "key_manager",
        "keystone_authtoken",
        "nova",
        "oslo_concurrency",
        "oslo_messaging_amqp",
        "oslo_messaging_kafka",
        "oslo_messaging_notifications",
        "oslo_messaging_rabbit",
        "oslo_middleware",
        "oslo_policy",
        "oslo_reports",
        "oslo_versionedobjects",
        "privsep",
        "profiler",
        "sample_castellan_source",
        "sample_remote_file_source",
        "service_user",
        "ssl",
        "vault",
    };

    SetupConfig(sections, config);
}

/**
 * Set the defaults.
 */
static void
SetDefaults(
    Configs& config,
    const CubeRole_e role)
{
    config["DEFAULT"]["state_path"] = STATDIR;
    config["DEFAULT"]["restore_discard_excess_bytes"] = "true";
    config["DEFAULT"]["scheduler_default_filters"] = "AvailabilityZoneFilter,CapabilitiesFilter";
    config["DEFAULT"]["osapi_volume_workers"] = std::to_string(GetControlWorkers(IsConverged(role), IsEdge(role)));
    config["DEFAULT"]["enable_force_upload"] = "true";
    config["DEFAULT"]["allow_availability_zone_fallback"] = "true";

    config["oslo_concurrency"]["lock_path"] = "/var/lib/cinder/tmp";
    config["oslo_reports"]["log_dir"] = "/var/log/cinder";
}

/**
 * Set the endpoint of the process.
 */
static void
SetEndpoint(Configs& config, const std::string ctrlIp)
{
    config["DEFAULT"]["my_ip"] = ctrlIp;
    config["DEFAULT"]["osapi_volume_listen"] = ctrlIp;
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
    uri << "mysql+pymysql://cinder:" << dbPass << "@" << sharedId << "/cinder";

    config["database"]["connection"] = uri.str();
    // reconnect on a lost DB connection (survive the set_ready VIP/galera reconfig)
    config["database"]["use_db_reconnect"] = "true";
    config["database"]["db_max_retries"] = "-1";
    config["database"]["db_retry_interval"] = "1";
    config["database"]["db_inc_retry_interval"] = "true";
    config["database"]["db_max_retry_interval"] = "10";
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
    const std::string cinderPass)
{
    config["DEFAULT"]["auth_strategy"] = "keystone";

    config["keystone_authtoken"]["auth_type"] = "password";
    config["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";
    config["keystone_authtoken"]["http_connect_timeout"] = "15";
    config["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
    config["keystone_authtoken"]["memcached_servers"] = sharedId + ":11211";
    config["keystone_authtoken"]["project_domain_name"] = domain;
    config["keystone_authtoken"]["project_name"] = "service";
    config["keystone_authtoken"]["user_domain_name"] = domain;
    config["keystone_authtoken"]["username"] = "cinder";
    config["keystone_authtoken"]["password"] = cinderPass;
    config["keystone_authtoken"]["service_token_roles"] = "service";
    config["keystone_authtoken"]["service_token_roles_required"] = "true";
}

/**
 * Set infos for Nova, for supporting online volume expansion.
 */
static void
SetNovaInfo(
    Configs& config,
    const std::string sharedId,
    const std::string region,
    const std::string domain,
    const std::string novaPass)
{
    config["nova"]["auth_type"] = "password";
    config["nova"]["auth_url"] = "http://" + sharedId + ":5000";
    config["nova"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
    config["nova"]["memcached_servers"] = sharedId + ":11211";
    config["nova"]["region_name"] = region;
    config["nova"]["project_domain_name"] = domain;
    config["nova"]["project_name"] = "service";
    config["nova"]["user_domain_name"] = domain;
    config["nova"]["username"] = "nova";
    config["nova"]["password"] = novaPass;
}

/**
 * Set the connection to Ceph RBD as the built-in Cinder volume service.
 */
static void
SetCeph(
    Configs& config,
    const std::string virshSecret)
{
    config[BUILTIN_STORAGE_BACKEND]["backend_host"] = BUILTIN_STORAGE_HOST;
    config[BUILTIN_STORAGE_BACKEND]["volume_backend_name"] = BUILTIN_STORAGE_BACKEND;
    config[BUILTIN_STORAGE_BACKEND]["volume_driver"] = "cinder.volume.drivers.rbd.RBDDriver";
    config[BUILTIN_STORAGE_BACKEND]["rbd_ceph_conf"] = "/etc/ceph/ceph.conf";
    config[BUILTIN_STORAGE_BACKEND]["rbd_pool"] = VOLUME;
    config[BUILTIN_STORAGE_BACKEND]["rbd_user"] = "admin";
    config[BUILTIN_STORAGE_BACKEND]["rbd_secret_uuid"] = virshSecret;
    config[BUILTIN_STORAGE_BACKEND]["rados_connect_timeout"] = "-1";
    config[BUILTIN_STORAGE_BACKEND]["rbd_store_chunk_size"] = "4";
    config[BUILTIN_STORAGE_BACKEND]["rbd_max_clone_depth"] = "5";
    config[BUILTIN_STORAGE_BACKEND]["rbd_flatten_volume_from_snapshot"] = "false";
    config[BUILTIN_STORAGE_BACKEND]["image_upload_use_cinder_backend"] = "true";
}

/**
 * Set the connection to the backend of cinder-backup.
 */
static void
SetBackup(
    Configs& config,
    const bool override,
    const std::string type,
    const std::string sharedId,
    const std::string endpoint,
    const std::string account,
    const std::string secret,
    const std::string pool)
{
    if (override) {
        if (type == "cube-storage") {
            std::string conf = "/etc/cinder/ceph_backup.conf";
            HexUtilSystemF(
                0,
                0,
                HEX_SDK " ceph_basic_config_gen %s %s %s",
                conf.c_str(),
                endpoint.c_str(),
                secret.c_str());

            config["DEFAULT"]["backup_driver"] = "cinder.backup.drivers.ceph.CephBackupDriver";
            config["DEFAULT"]["backup_ceph_conf"] = conf;
            config["DEFAULT"]["backup_ceph_pool"] = BACKUP;
            config["DEFAULT"]["backup_ceph_user"] = "admin";
            config["DEFAULT"]["backup_ceph_chunk_size"] = "134217728";
            config["DEFAULT"]["backup_ceph_stripe_count"] = "0";
            config["DEFAULT"]["backup_ceph_stripe_unit"] = "0";
        } else if (type == "cube-swift") {
            config["DEFAULT"]["backup_driver"] = "cinder.backup.drivers.swift.SwiftBackupDriver";
            config["DEFAULT"]["backup_swift_auth_url"] = "http://" + endpoint + ":5000/v3";
            config["DEFAULT"]["backup_swift_auth_version"] = "3";
            config["DEFAULT"]["backup_swift_auth"] = "single_user";
            config["DEFAULT"]["backup_swift_user"] = account;
            config["DEFAULT"]["backup_swift_user_domain"] = "default";
            config["DEFAULT"]["backup_swift_key"] = secret;
            config["DEFAULT"]["backup_swift_container"] = BACKUP;
            config["DEFAULT"]["backup_swift_object_size"] = "134217728";
            config["DEFAULT"]["backup_swift_project"] = pool;
            config["DEFAULT"]["backup_swift_project_domain"] = "default";
            config["DEFAULT"]["backup_swift_retry_attempts"] = "3";
            config["DEFAULT"]["backup_swift_retry_backoff"] = "2";
            config["DEFAULT"]["backup_compression_algorithm"] = "zlib";
        }

        return;
    }

    // default settings
    config["DEFAULT"]["backup_driver"] = "cinder.backup.drivers.swift.SwiftBackupDriver";
    config["DEFAULT"]["backup_swift_url"] = "http://" + sharedId + ":8890/v1/AUTH_";
    config["DEFAULT"]["backup_swift_auth_url"] = "http://" + sharedId + ":5000/v3";
    config["DEFAULT"]["backup_swift_auth"] = "per_user";
    config["DEFAULT"]["backup_swift_auth_version"] = "1";
    config["DEFAULT"]["backup_swift_user"] = "None";
    config["DEFAULT"]["backup_swift_user_domain"] = "None";
    config["DEFAULT"]["backup_swift_key"] = "None";
    config["DEFAULT"]["backup_swift_container"] = BACKUP;
    config["DEFAULT"]["backup_swift_object_size"] = "134217728";
    config["DEFAULT"]["backup_swift_project"] = "None";
    config["DEFAULT"]["backup_swift_project_domain"] = "None";
    config["DEFAULT"]["backup_swift_retry_attempts"] = "3";
    config["DEFAULT"]["backup_swift_retry_backoff"] = "2";
    config["DEFAULT"]["backup_compression_algorithm"] = "zlib";
}

/**
 * Set the storage backends.
 */
static void
SetStorageBackend(
    Configs& config,
    const std::string defaultVolumeType)
{
    // move exta config files for external storage backends to Cinder config directory
    std::string fsError;
    bool fileExists = false;

    fileExists = HasFileMatchGlob(fsError, CONF_DIR, "ext_storage_*.conf");
    if (fsError != "") {
        HexLogError("%s", fsError.c_str());
    } else if (fileExists) {
        HexSystemF(0, "rm -f %s/ext_storage_*.conf", CONF_DIR);
    }

    fileExists = HasFileMatchGlob(fsError, CINDER_BACKEND_DIR, "ext_storage_*.conf");
    if (fsError != "") {
        HexLogError("%s", fsError.c_str());
    } else if (fileExists) {
        HexSystemF(0, "cp -f %s/ext_storage_*.conf %s/", CINDER_BACKEND_DIR, CONF_DIR);
    }

    // set backends into the config
    std::stringstream enabledBackendLine;
    enabledBackendLine << BUILTIN_STORAGE_BACKEND;
    for (std::vector<ConfigString>::const_iterator it = s_storageBackends.begin(); it != s_storageBackends.end(); it++) {
        if (it->newValue().length() == 0) {
            continue;
        }

        enabledBackendLine << "," << it->newValue();
    }

    config["DEFAULT"]["allowed_direct_url_schemes"] = "cinder";
    config["DEFAULT"]["glance_request_timeout"] = "1200";
    config["DEFAULT"]["enabled_backends"] = enabledBackendLine.str();
    config["DEFAULT"]["default_volume_type"] = defaultVolumeType;
}

/**
 * Set the debug toggle.
 */
static void
SetDebug(
    Configs& config,
    const bool enabled)
{
    config["DEFAULT"]["debug"] = enabled ? "true" : "false";
}

/**
 * Set up Cinder service.
 * The function should be run after Keystone service is running.
 */
static void
SetupService(const std::string domain, const std::string userPass)
{
    HexLogInfo("Setting up cinder");

    // populate the cinder service database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"cinder-manage db sync\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // create the cinder service credentials
    HexUtilSystemF(
        0,
        0,
        "%s %s user create --domain %s --password %s cinder",
        env.c_str(),
        OPENSTACK_CLI,
        domain.c_str(),
        userPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user cinder admin", env.c_str(), OPENSTACK_CLI);
    HexUtilSystemF(0, 0, "%s %s role add --project service --user cinder service", env.c_str(), OPENSTACK_CLI);

    // create the service entity
    HexUtilSystemF(
        0,
        0,
        "%s %s service create --name cinderv2 --description \"OpenStack Block Storage\" volumev2",
        env.c_str(),
        OPENSTACK_CLI);
    HexUtilSystemF(
        0,
        0,
        "%s %s service create --name cinderv3 --description \"OpenStack Block Storage\" volumev3",
        env.c_str(),
        OPENSTACK_CLI);
}

/**
 * Set service endpoints.
 */
static void
SetServiceEndpoints(
    std::string endpoint,
    std::string external,
    std::string region)
{
    HexLogInfo("Updating cinder endpoint");

    const std::string publicUrlV2 = "http://" + external + ":8776/v2/%\\(project_id\\)s";
    const std::string adminUrlV2 = "http://" + endpoint + ":8776/v2/%\\(project_id\\)s";
    const std::string internalUrlV2 = "http://" + endpoint + ":8776/v2/%\\(project_id\\)s";

    HexUtilSystemF(
        0,
        0,
        HEX_SDK " os_endpoint_update %s %s %s %s %s",
        "volumev2",
        region.c_str(),
        publicUrlV2.c_str(),
        adminUrlV2.c_str(),
        internalUrlV2.c_str());

    const std::string publicUrlV3 = "http://" + external + ":8776/v3/%\\(project_id\\)s";
    const std::string adminUrlV3 = "http://" + endpoint + ":8776/v3/%\\(project_id\\)s";
    const std::string internalUrlV3 = "http://" + endpoint + ":8776/v3/%\\(project_id\\)s";

    HexUtilSystemF(
        0,
        0,
        HEX_SDK " os_endpoint_update %s %s %s %s %s",
        "volumev3",
        region.c_str(),
        publicUrlV3.c_str(),
        adminUrlV3.c_str(),
        internalUrlV3.c_str());
}

/**
 * Start Cinder services.
 */
static void
StartCinderService(const bool enabled, const bool isHa, const bool isBootstrap, const bool isMaster)
{
    SystemdCommitService(enabled, API_NAME); // cinder-api
    SystemdCommitService(enabled, SCHL_NAME); // cinder-scheduler
    SystemdCommitService(enabled, BAK_NAME); // cinder-backup
    if (!isHa) {
        SystemdCommitService(enabled, VOL_NAME); // cinder-volume
    } else if (!isBootstrap && isMaster) {
        // cinder-volume is a pacemaker singleton; restart it master-only so
        // concurrent peers don't race the CIB target-role.
        HexUtilSystemF(0, 0, "pcs resource restart cinder-volume");
    }
}

/**
 * Create volume types.
 */
static void
CreateVolumeTypes(const TuningStringArray& storageBackends)
{
    std::stringstream typesLine;
    typesLine << BUILTIN_VOLUME_TYPE;

    /**
     * We would set a convention here,
     * volume type would be the same as storage backend (service & volume backend)
     * for non built-in storage backends.
     */
    for (std::vector<ConfigString>::const_iterator it = storageBackends.begin(); it != storageBackends.end(); it++) {
        std::string storageBackendName = it->newValue();
        if (storageBackendName.length() == 0) {
            continue;
        }

        typesLine << "," << storageBackendName;
        HexUtilSystemF(0, 0, HEX_SDK " os_volume_type_create %s %s", storageBackendName.c_str(), storageBackendName.c_str());
    }

    HexUtilSystemF(0, 0, HEX_SDK " os_volume_type_clear %s", typesLine.str().c_str());
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    /**
     * Sync models and multipath settings from control nodes,
     * for pure compute nodes during bootstrapping.
     */
    if (IsCompute(s_eCubeRole) && !IsControl(s_eCubeRole) && IsBootstrap()) {
        const ExecSyncResult r = ExecBashSync(
            0,
            false,
            false,
            {},
            HEX_SDK " cinder_sync_models_from_control");
        if (r.exitCode != 0) {
            HexLogError("failed to sync models from controls to this pure compute node");
        }
    }

    // we only run Cinder services on control nodes
    if (!IsControl(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    std::string ctrlIp = G(CTRL_IP);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    std::string cinderPass = GetSaltKey(s_saltkey, s_cinderPass.newValue(), s_seed.newValue());
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass.newValue(), s_seed.newValue());
    std::string novaPass = GetSaltKey(s_saltkey, s_novaPass.newValue(), s_seed.newValue());
    std::string virshSecret = HexUtilPOpen(HEX_SDK " os_cinder_virsh_secret_create %s", s_seed.c_str());

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
    if (s_bDbPassChanged)
        MysqlUtilUpdateDbPass(USER, dbPass.c_str());

    // set up the Ceph RBD pools
    SetupRbdPools();

    // configure the services
    if (s_bConfigChanged) {
        std::string domain = s_cubeDomain.newValue();

        LoadDefaultConfig(mainConfig);
        InitConfig(mainConfig);
        SetDefaults(mainConfig, s_eCubeRole);
        SetEndpoint(mainConfig, ctrlIp);
        SetDatabaseConnection(mainConfig, sharedId, dbPass);
        SetWorkerQueue(mainConfig, s_ha, sharedId, mqPass, s_ctrlAddrs);
        SetNotificationQueue(mainConfig, sharedId);
        SetAuth(mainConfig, sharedId, domain, cinderPass);
        SetNovaInfo(mainConfig, sharedId, s_cubeRegion, domain, novaPass);
        SetCeph(mainConfig, virshSecret);
        if (s_volumeTypeDefault.newValue() != "") {
            SetStorageBackend(mainConfig, s_volumeTypeDefault);
        } else {
            SetStorageBackend(mainConfig, BUILTIN_VOLUME_TYPE);
        }
        SetBackup(
            mainConfig,
            s_backupOverride,
            s_backupType,
            sharedId,
            s_backupEndpoint,
            s_backupAccount,
            s_backupSecret,
            s_backupPool);
        SetDebug(mainConfig, s_debug);

        // write back to cinder config files
        WriteConfig(CONF, SB_SEC_WFMT, '=', mainConfig);
    }

    if (!s_bSetup) {
        // set up the service (services must be running)
        SetupService(s_cubeDomain, cinderPass);
    }

    // migrate db
    HexUtilSystemF(0, 0, HEX_SDK " migrate_cinder_db");

    if (s_bEndpointChanged) {
        SetServiceEndpoints(sharedId, external, s_cubeRegion);
    }

    // start services
    StartCinderService(s_enabled, s_ha, IsBootstrap(), G(IS_MASTER));
    // wait for services to be up
    std::stringstream enabledHostLine;
    enabledHostLine << BUILTIN_STORAGE_HOST << "@" << BUILTIN_STORAGE_BACKEND;
    for (std::vector<ConfigString>::const_iterator it = s_storageBackends.begin(); it != s_storageBackends.end(); it++) {
        if (it->newValue().length() == 0) {
            continue;
        }

        enabledHostLine << "," << it->newValue() << "@" << it->newValue();
    }
    HexUtilSystemF(
        0,
        0,
        "%s cinder_wait_for_services_up %s",
        HEX_SDK,
        enabledHostLine.str().c_str());

    // create the volume type
    if (s_bStorageBackendChanged)
        CreateVolumeTypes(s_storageBackends);

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_cinder\n", HexLogProgramName());
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
    StartCinderService(s_enabled, s_ha, IsBootstrap(), G(IS_MASTER));

    return EXIT_SUCCESS;
}

/**
 * Add a Ceph pool as a storage backend.
 */
static void
AddCephPoolAsStorageBackend(
    Configs& config,
    const std::string pool)
{
    config[pool]["backend_host"] = BUILTIN_STORAGE_HOST;
    config[pool]["volume_backend_name"] = pool;
    config[pool]["rbd_pool"] = pool;
    config[pool]["volume_driver"] = "cinder.volume.drivers.rbd.RBDDriver";
    config[pool]["rbd_ceph_conf"] = "/etc/ceph/ceph.conf";
    config[pool]["rbd_user"] = "admin";
    if (config.count(BUILTIN_STORAGE_BACKEND) > 0 && config[BUILTIN_STORAGE_BACKEND].count("rbd_secret_uuid") > 0) {
        config[pool]["rbd_secret_uuid"] = config[BUILTIN_STORAGE_BACKEND]["rbd_secret_uuid"];
    } else {
        config[pool]["rbd_secret_uuid"] = HexUtilPOpen(HEX_SDK " os_cinder_virsh_secret_create %s", s_seed.c_str());
    }
    config[pool]["rados_connect_timeout"] = "-1";
    config[pool]["rbd_store_chunk_size"] = "4";
    config[pool]["rbd_max_clone_depth"] = "5";
    config[pool]["rbd_flatten_volume_from_snapshot"] = "false";
    config[pool]["image_upload_use_cinder_backend"] = "true";
}

static void
ReconfigUsage(void)
{
    fprintf(stderr, "Usage: %s reconfig_cinder \n", HexLogProgramName());
}

static int
ReconfigMain(int argc, char* argv[])
{
    bool enabled = s_enabled;
    if (!enabled || !IsControl(s_eCubeRole))
        return EXIT_SUCCESS;

    static Configs currentConfig;
    if (!LoadConfig(CONF, SB_SEC_RFMT, '=', currentConfig)) {
        HexLogError("failed to load existing cinder config file %s", CONF);
        return EXIT_FAILURE;
    }

    // user-defined node groups are mapped with *-pool/*-ssd, respectively
    std::string customPools = HexUtilPOpen("timeout 30 ceph osd pool ls | grep -e '[-]pool' -e '[-]ssd' | tr '\n' ' '");

    std::stringstream enabledBackendLine;
    int index = 0;

    // filter away existing node group storage backend configs
    std::vector<std::string> existingStorageBackends = hex_string_util::split(currentConfig["DEFAULT"]["enabled_backends"], ',');
    for (std::vector<std::string>::const_iterator it = existingStorageBackends.begin(); it != existingStorageBackends.end(); it++) {
        if (it->find("-pool") == std::string::npos && it->find("-ssd") == std::string::npos) {
            // keep storage backends not related to "*-pool" and "*-ssd"
            if (index == 0) {
                enabledBackendLine << *it;
            } else {
                enabledBackendLine << "," << *it;
            }
            ++index;
        } else {
            // drop the config section
            if (currentConfig.count(*it) > 0) {
                currentConfig.erase(*it);
            }
        }
    }

    for (int start = 0, end = 0; (start < (int)customPools.length()) && (end != -1); start = end + 1) {
        end = customPools.find(" ", start);
        std::string pool = customPools.substr(start, end - start);

        AddCephPoolAsStorageBackend(currentConfig, pool);

        if (index == 0) {
            enabledBackendLine << pool;
        } else {
            enabledBackendLine << "," << pool;
        }
        ++index;
    }
    currentConfig["DEFAULT"]["enabled_backends"] = enabledBackendLine.str();

    const bool writeSuccess = WriteConfig(CONF, SB_SEC_WFMT, '=', currentConfig);
    return writeSuccess ? EXIT_SUCCESS : EXIT_FAILURE;
}

static int
ClusterStartMain(int argc, char** argv)
{
    if (argc != 1)
        return EXIT_FAILURE;

    // default volume type
    if (IsControl(s_eCubeRole)) {
        ReconfigMain(0, NULL);
        HexUtilSystemF(
            0,
            0,
            "%s os_volume_type_create %s %s",
            HEX_SDK,
            BUILTIN_VOLUME_TYPE,
            BUILTIN_STORAGE_BACKEND);
    }

    return EXIT_SUCCESS;
}

CONFIG_MODULE(cinder, Init, Parse, 0, 0, Commit);
// startup sequence
CONFIG_REQUIRES(cinder, keystone);
CONFIG_REQUIRES(cinder, memcache);
CONFIG_REQUIRES(cinder, libvirtd);
CONFIG_REQUIRES(cinder, ceph);

CONFIG_MIGRATE(cinder, "/etc/cube/cos/cinder");
CONFIG_MIGRATE(cinder, CINDER_BACKEND_DIR);
CONFIG_MIGRATE(cinder, "/etc/cinder/external_storage_extra_configs");
CONFIG_MIGRATE(cinder, CONF_DIR);
CONFIG_MIGRATE(cinder, MAKRER_POOL);

// extra tunings
CONFIG_OBSERVES(cinder, rabbitmq, ParseRabbitMQ, NotifyRabbitMQ);
CONFIG_OBSERVES(cinder, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(cinder, nova, ParseNova, NotifyNova);

CONFIG_TRIGGER_WITH_SETTINGS(cinder, "cluster_start", ClusterStartMain);

CONFIG_COMMAND_WITH_SETTINGS(restart_cinder, RestartMain, RestartUsage);
CONFIG_COMMAND_WITH_SETTINGS(reconfig_cinder, ReconfigMain, ReconfigUsage);
