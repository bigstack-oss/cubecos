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
#include <cube/systemd_util.h>

#include "mysql_util.h"
#include "include/role_cubesys.h"

static const char USER[] = "cinder";
static const char GROUP[] = "cinder";
static const char VOLUME[] = "cinder-volumes";
static const char BACKUP[] = "volume-backups";

// cinder config files
#define DEF_EXT     ".def"
#define CONF        "/etc/cinder/cinder.conf"
#define MAKRER_POOL "/etc/appliance/state/cinder_pool_done"

// cinder common
static const char RUNDIR[] = "/run/cinder";
static const char STATDIR[] = "/store/cinder";
static const char BACKENDDIR[] = "/etc/cinder/backends";

// cinder-backup
static const char API_NAME[] = "openstack-cinder-api";

// cinder-scheduler
static const char SCHL_NAME[] = "openstack-cinder-scheduler";

// cinder-volume
static const char VOL_NAME[] = "openstack-cinder-volume";

// cinder-backup
static const char BAK_NAME[] = "openstack-cinder-backup";

static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char USERPASS[] = "8YHpMKC1394HbTmL";
static const char DBPASS[] = "hhyCDG3IdNmcQaJo";

static const char OSCMD[] = "/usr/bin/openstack";

static Configs cfg;

static bool s_bSetup = true;

static bool s_bMqModified = false;
static bool s_bCubeModified = false;
static bool s_bNovaModified = false;

static bool s_bDbPassChanged = false;
static bool s_bEndpointChanged = false;
static bool s_bConfigChanged = false;
static bool s_bExternalChanged = false;

static CubeRole_e s_eCubeRole;

// external global variables
CONFIG_GLOBAL_STR_REF(CTRL_IP);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(CINDER_ENABLED, "cinder.enabled", TUNING_UNPUB, "Set to true to enable cinder.", true);
CONFIG_TUNING_STR(CINDER_USERPASS, "cinder.user.password", TUNING_UNPUB, "Set cinder user password.", USERPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_DBPASS, "cinder.db.password", TUNING_UNPUB, "Set cinder database password.", DBPASS, ValidateRegex, DFT_REGEX_STR);

// public tunigns
CONFIG_TUNING_BOOL(CINDER_DEBUG, "cinder.debug.enabled", TUNING_PUB, "Set to true to enable cinder verbose log.", false);
CONFIG_TUNING_STR(CINDER_EXTERNAL_NAME, "cinder.external.%d.name", TUNING_PUB, "Set cinder external storage rule name.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_EXTERNAL_DRIVER, "cinder.external.%d.driver", TUNING_PUB, "Set cinder external storage type name <cube|purestorage>.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_EXTERNAL_ENDPOINT, "cinder.external.%d.endpoint", TUNING_PUB, "Set cinder external storage endpoint.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_EXTERNAL_POOL, "cinder.external.%d.pool", TUNING_PUB, "Set cinder external storage pool.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_EXTERNAL_ACCOUNT, "cinder.external.%d.account", TUNING_PUB, "Set cinder external storage account.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CINDER_EXTERNAL_SECRET, "cinder.external.%d.secret", TUNING_PUB, "Set cinder external storage account secret.", "", ValidateRegex, DFT_REGEX_STR);
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
PARSE_TUNING_STR_ARRAY(s_extNameArr, CINDER_EXTERNAL_NAME);
PARSE_TUNING_STR_ARRAY(s_extDriverArr, CINDER_EXTERNAL_DRIVER);
PARSE_TUNING_STR_ARRAY(s_extEndpointArr, CINDER_EXTERNAL_ENDPOINT);
PARSE_TUNING_STR_ARRAY(s_extAccountArr, CINDER_EXTERNAL_ACCOUNT);
PARSE_TUNING_STR_ARRAY(s_extSecretArr, CINDER_EXTERNAL_SECRET);
PARSE_TUNING_STR_ARRAY(s_extPoolArr, CINDER_EXTERNAL_POOL);
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

static bool
PoolSetup(void)
{
    if (access(MAKRER_POOL, F_OK) != 0) {
        // Create the cinder volume/backup storage
        HexUtilSystemF(0, 0, HEX_SDK " ceph_create_pool %s rbd", VOLUME);
        HexUtilSystemF(0, 0, HEX_SDK " ceph_create_pool %s rbd", BACKUP);
        HexUtilSystemF(0, 0, "timeout 10 ceph osd pool set %s bulk true", VOLUME);

        HexSystemF(0, "touch " MAKRER_POOL);
    }
    return true;
}

// depends on mysqld (called inside commit())
static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if(!MysqlUtilIsDbExist("cinder")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE cinder") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY 'cinder_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY 'cinder_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

// Setup should run after keystone & cinder services are running.
static bool
SetupCinder(std::string domain, std::string userPass)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up cinder");

    // Populate the cinder service database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"cinder-manage db sync\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the cinder service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s cinder",
                         env.c_str(), OSCMD, domain.c_str(), userPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user cinder admin", env.c_str(), OSCMD);
    HexUtilSystemF(0, 0, "%s %s role add --project service --user cinder service", env.c_str(), OSCMD);

    // Create the service entity
    HexUtilSystemF(0, 0, "%s %s service create --name cinderv2 "
                         "--description \"OpenStack Block Storage\" volumev2",
                         env.c_str(), OSCMD);

    // Create the service entity
    HexUtilSystemF(0, 0, "%s %s service create --name cinderv3 "
                         "--description \"OpenStack Block Storage\" volumev3",
                         env.c_str(), OSCMD);

    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating cinder endpoint");

    std::string pub = "http://" + external + ":8776/v2/%\\(project_id\\)s";
    std::string adm = "http://" + endpoint + ":8776/v2/%\\(project_id\\)s";
    std::string intr = "http://" + endpoint + ":8776/v2/%\\(project_id\\)s";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "volumev2", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    pub = "http://" + external + ":8776/v3/%\\(project_id\\)s";
    adm = "http://" + endpoint + ":8776/v3/%\\(project_id\\)s";
    intr = "http://" + endpoint + ":8776/v3/%\\(project_id\\)s";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "volumev3", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static bool
UpdateDbConn(std::string sharedId, std::string password)
{
    if(IsControl(s_eCubeRole)) {
        std::string dbconn = "mysql+pymysql://cinder:";
        dbconn += password;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/cinder";

        cfg["database"]["connection"] = dbconn;
    }

    return true;
}

static bool
UpdateControllerIp(std::string ctrlIp)
{
    if(IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["my_ip"] = ctrlIp;
        cfg["DEFAULT"]["osapi_volume_listen"] = ctrlIp;
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
        cfg["keystone_authtoken"]["service_token_roles"] = "service";
        cfg["nova"]["memcached_servers"] = sharedId + ":11211";
        cfg["nova"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["nova"]["auth_url"] = "http://" + sharedId + ":5000";
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
        cfg["keystone_authtoken"]["service_token_roles_required"] = "true";

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
UpdateBackup(bool override, const std::string &type, const std::string &sharedId,
             const std::string &endpoint, const std::string &account,
             const std::string &secret, const std::string &pool)
{
    if (!IsControl(s_eCubeRole))
        return true;

    if (override) {
        if (type == "cube-storage") {
            std::string conf = "/etc/cinder/ceph_backup.conf";
            HexUtilSystemF(0, 0, HEX_SDK " ceph_basic_config_gen %s %s %s",
                                 conf.c_str(), endpoint.c_str(), secret.c_str());
            cfg["DEFAULT"]["backup_ceph_chunk_size"] = "134217728";
            cfg["DEFAULT"]["backup_ceph_user"] = "admin";
            cfg["DEFAULT"]["backup_ceph_conf"] = conf;
            cfg["DEFAULT"]["backup_ceph_pool"] = BACKUP;
            cfg["DEFAULT"]["backup_ceph_stripe_count"] = "0";
            cfg["DEFAULT"]["backup_ceph_stripe_unit"] = "0";
            cfg["DEFAULT"]["backup_driver"] = "cinder.backup.drivers.ceph.CephBackupDriver";
            return true;
        }
        if (type == "cube-swift") {
            cfg["DEFAULT"]["backup_swift_auth_url"] = "http://" + endpoint + ":5000/v3";
            cfg["DEFAULT"]["backup_swift_auth_version"] = "3";
            cfg["DEFAULT"]["backup_swift_auth"] = "single_user";
            cfg["DEFAULT"]["backup_swift_user"] = account;
            cfg["DEFAULT"]["backup_swift_user_domain"] = "default";
            cfg["DEFAULT"]["backup_swift_key"] = secret;
            cfg["DEFAULT"]["backup_swift_container"] = BACKUP;
            cfg["DEFAULT"]["backup_swift_object_size"] = "134217728";
            cfg["DEFAULT"]["backup_swift_project"] = pool;
            cfg["DEFAULT"]["backup_swift_project_domain"] = "default";
            cfg["DEFAULT"]["backup_swift_retry_attempts"] = "3";
            cfg["DEFAULT"]["backup_swift_retry_backoff"] = "2";
            cfg["DEFAULT"]["backup_compression_algorithm"] = "zlib";
            cfg["DEFAULT"]["backup_driver"] = "cinder.backup.drivers.swift.SwiftBackupDriver";
            return true;
        }
    }

    // default settings
    cfg["DEFAULT"]["backup_swift_url"] = "http://" + sharedId + ":8890/v1/AUTH_";
    cfg["DEFAULT"]["backup_swift_auth_url"] = "http://" + sharedId + ":5000/v3";
    cfg["DEFAULT"]["backup_swift_auth"] = "per_user";
    cfg["DEFAULT"]["backup_swift_auth_version"] = "1";
    cfg["DEFAULT"]["backup_swift_user"] = "None";
    cfg["DEFAULT"]["backup_swift_user_domain"] = "None";
    cfg["DEFAULT"]["backup_swift_key"] = "None";
    cfg["DEFAULT"]["backup_swift_container"] = BACKUP;
    cfg["DEFAULT"]["backup_swift_object_size"] = "134217728";
    cfg["DEFAULT"]["backup_swift_project"] = "None";
    cfg["DEFAULT"]["backup_swift_project_domain"] = "None";
    cfg["DEFAULT"]["backup_swift_retry_attempts"] = "3";
    cfg["DEFAULT"]["backup_swift_retry_backoff"] = "2";
    cfg["DEFAULT"]["backup_compression_algorithm"] = "zlib";
    cfg["DEFAULT"]["backup_driver"] = "cinder.backup.drivers.swift.SwiftBackupDriver";

    return true;
}

static bool
UpdateStorage(void)
{
    std::string enabledBackends = "ceph";

    for (unsigned i = 0 ; i < s_extNameArr.size() ; i++) {
        if (s_extNameArr.newValue(i).length() == 0)
            continue;

        std::string name = s_extNameArr.newValue(i);
        std::string driver, endpoint, account, secret, pool;

        driver = endpoint = account = secret = pool = "";

        if (i < s_extDriverArr.size())
            driver = s_extDriverArr.newValue(i);
        if (i < s_extEndpointArr.size())
            endpoint = s_extEndpointArr.newValue(i);
        if (i < s_extAccountArr.size())
            account = s_extAccountArr.newValue(i);
        if (i < s_extSecretArr.size())
            secret = s_extSecretArr.newValue(i);
        if (i < s_extPoolArr.size())
            pool = s_extPoolArr.newValue(i);

        enabledBackends += "," + name;

        cfg[name]["backend_host"] = "cube";
        cfg[name]["volume_backend_name"] = name;
        if (driver == "cube") {
            std::string conf = std::string(BACKENDDIR) + "/" + name + ".conf";
            HexUtilSystemF(0, 0, HEX_SDK " ceph_basic_config_gen %s %s %s",
                                 conf.c_str(), endpoint.c_str(), secret.c_str());
            std::string uuid = HexUtilPOpen(HEX_SDK " os_cinder_virsh_secret_create %s %s %s",
                                            name.c_str(), endpoint.c_str(), secret.c_str());
            cfg[name]["volume_driver"] = "cinder.volume.drivers.rbd.RBDDriver";
            cfg[name]["rbd_user"] = "admin";
            cfg[name]["rbd_secret_uuid"] = uuid;
            cfg[name]["rbd_pool"] = pool;
            cfg[name]["rbd_ceph_conf"] = conf;
            cfg[name]["rbd_flatten_volume_from_snapshot"] = "false";
            cfg[name]["rbd_max_clone_depth"] = "5";
            cfg[name]["rbd_store_chunk_size"] = "4";
            cfg[name]["rados_connect_timeout"] = "-1";
            cfg[name]["image_upload_use_cinder_backend"] = "true";
        }
        if (driver == "purestorage") {
            cfg[name]["volume_driver"] = "cinder.volume.drivers.pure.PureISCSIDriver";
            cfg[name]["san_ip"] = endpoint;
            cfg[name]["pure_api_token"] = secret;
            cfg[name]["use_multipath_for_image_xfer"] = "true";
        }
    }

    cfg["DEFAULT"]["enabled_backends"] = enabledBackends;
    cfg["DEFAULT"]["default_volume_type"] = "CubeStorage";

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
UpdateCfg(const std::string& domain, const std::string& region,
          const std::string& userPass, const std::string& novaPass, const std::string& virshSecret)
{
    if(IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["auth_strategy"] = "keystone";
        cfg["DEFAULT"]["log_dir"] = "/var/log/cinder";
        cfg["DEFAULT"]["glance_api_version"] = "2";
        cfg["DEFAULT"]["state_path"] = STATDIR;

        cfg["DEFAULT"]["restore_discard_excess_bytes"] = "true";
        cfg["DEFAULT"]["scheduler_default_filters"] = "AvailabilityZoneFilter,CapabilitiesFilter";
        cfg["DEFAULT"]["osapi_volume_workers"] = std::to_string(GetControlWorkers(IsConverged(s_eCubeRole), IsEdge(s_eCubeRole)));
        cfg["DEFAULT"]["enable_force_upload"] = "true";
        cfg["DEFAULT"]["allow_availability_zone_fallback"] = "true";

        cfg["backend_defaults"]["volume_driver"] = "cinder.volume.drivers.rbd.RBDDriver";
        cfg["backend_defaults"]["rbd_user"] = "admin";
        cfg["backend_defaults"]["rbd_secret_uuid"] = virshSecret;
        cfg["backend_defaults"]["rbd_ceph_conf"] = "/etc/ceph/ceph.conf";
        cfg["backend_defaults"]["rbd_flatten_volume_from_snapshot"] = "false";
        cfg["backend_defaults"]["rbd_max_clone_depth"] = "5";
        cfg["backend_defaults"]["rbd_store_chunk_size"] = "4";
        cfg["backend_defaults"]["rados_connect_timeout"] = "-1";
        cfg["backend_defaults"]["image_upload_use_cinder_backend"] = "true";

        cfg["ceph"]["volume_backend_name"] = "ceph";
        cfg["ceph"]["rbd_pool"] = VOLUME;
        cfg["ceph"]["backend_host"] = "cube";

        cfg["keystone_authtoken"].clear();
        cfg["keystone_authtoken"]["auth_type"] = "password";
        cfg["keystone_authtoken"]["project_domain_name"] = domain.c_str();
        cfg["keystone_authtoken"]["user_domain_name"] = domain.c_str();
        cfg["keystone_authtoken"]["project_name"] = "service";
        cfg["keystone_authtoken"]["username"] = "cinder";
        cfg["keystone_authtoken"]["password"] = userPass.c_str();

        // For supporting online volume expansion
        cfg["nova"]["auth_type"] = "password";
        cfg["nova"]["project_domain_name"] = domain.c_str();
        cfg["nova"]["user_domain_name"] = domain.c_str();
        cfg["nova"]["region_name"] = region.c_str();
        cfg["nova"]["project_name"] = "service";
        cfg["nova"]["username"] = "nova";
        cfg["nova"]["password"] = novaPass.c_str();

        cfg["oslo_concurrency"]["lock_path"] = "/var/lib/cinder/tmp";

        cfg["oslo_messaging_notifications"]["driver"] = "messagingv2";
    }

    return true;
}

static bool
CinderService(bool enabled, bool ha)
{
    if(IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled, API_NAME);   // cinder-api
        SystemdCommitService(enabled, SCHL_NAME);   // cinder-scheduler
        SystemdCommitService(enabled, BAK_NAME);    // cinder-backup
        if (!ha)
            SystemdCommitService(enabled, VOL_NAME);    // cinder-volume
        else if (!IsBootstrap())
            HexUtilSystemF(0, 0, "pcs resource restart cinder-volume");
    }

    return true;
}

static bool
CinderVolumeType(void)
{
    if(!IsControl(s_eCubeRole))
        return true;

    std::string types = "CubeStorage";

    for (unsigned i = 0 ; i < s_extNameArr.size() ; i++) {
        if (s_extNameArr.newValue(i).length() == 0)
            continue;

        std::string name = s_extNameArr.newValue(i);
        types += "," + name;
        HexUtilSystemF(0, 0, HEX_SDK " os_volume_type_create %s %s", name.c_str(), name.c_str());
    }

    HexUtilSystemF(0, 0, HEX_SDK " os_volume_type_clear %s", types.c_str());

    return true;
}

static bool
Init()
{
    if (HexMakeDir(RUNDIR, USER, GROUP, 0755) != 0 ||
        HexMakeDir(BACKENDDIR, USER, GROUP, 0755) != 0)
        return false;

    // fail safe for creating state dir
    HexMakeDir(STATDIR, USER, GROUP, 0755);

    // load cinder configurations
    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', cfg)) {
        HexLogError("failed to load cinder config file %s", CONF);
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
    s_bNovaModified = s_novaPass.modified();
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        s_bConfigChanged = true;
        return true;
    }

    s_bDbPassChanged = s_dbPass.modified() | s_bCubeModified;

    s_bExternalChanged = s_extNameArr.modified() | s_extDriverArr.modified() |
                     s_extEndpointArr.modified() | s_extAccountArr.modified() |
                       s_extSecretArr.modified();

    s_bConfigChanged = modified | s_bMqModified | s_bCubeModified | s_bNovaModified | s_bExternalChanged |
                       G_MOD(CTRL_IP) | G_MOD(SHARED_ID);

    s_bEndpointChanged = s_bCubeModified | G_MOD(SHARED_ID) | G_MOD(EXTERNAL);

    return s_bDbPassChanged | s_bConfigChanged |
         s_bEndpointChanged | s_bExternalChanged;
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

    std::string cinderPass = GetSaltKey(s_saltkey, s_cinderPass.newValue(), s_seed.newValue());
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass.newValue(), s_seed.newValue());
    std::string novaPass = GetSaltKey(s_saltkey, s_novaPass.newValue(), s_seed.newValue());
    std::string virshSecret = HexUtilPOpen(HEX_SDK " os_cinder_virsh_secret_create %s", s_seed.c_str());

    SetupCheck();
    if (!s_bSetup) {
        s_bDbPassChanged = true;
        s_bEndpointChanged = true;
    }

    // 1. System Config
    if (s_bDbPassChanged && IsControl(s_eCubeRole))
        MysqlUtilUpdateDbPass(USER, dbPass.c_str());

    // 2. Service Config
    if (s_bConfigChanged) {
        UpdateCfg(s_cubeDomain.newValue(), s_cubeRegion.newValue(), cinderPass, novaPass, virshSecret);
        UpdateSharedId(sharedId);
        UpdateControllerIp(ctrlIp);
        UpdateDbConn(sharedId, dbPass);
        UpdateMqConn(s_ha, sharedId, mqPass, s_ctrlAddrs.newValue());
        UpdateDebug(s_debug.newValue());
        UpdateStorage();
        UpdateBackup(s_backupOverride, s_backupType, sharedId,
                     s_backupEndpoint, s_backupAccount, s_backupSecret, s_backupPool);

        // write back to cinder config files
        WriteConfig(CONF, SB_SEC_WFMT, '=', cfg);
    }

    // 3. Service Setup (service must be running)
    if (!s_bSetup)
        SetupCinder(s_cubeDomain.newValue(), cinderPass);

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_cinder_db");

    PoolSetup();

    if (s_bEndpointChanged)
        UpdateEndpoint(sharedId, external, s_cubeRegion.newValue());

    // 4. create volume type
    if (s_bExternalChanged)
        CinderVolumeType();

    // 5. Service kickoff
    CinderService(s_enabled, s_ha);

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

    CinderService(s_enabled, s_ha);

    return EXIT_SUCCESS;
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
    if (!enabled)
        return EXIT_SUCCESS;

    static Configs curCfg;
    if (!LoadConfig(CONF, SB_SEC_RFMT, '=', curCfg)) {
        HexLogError("failed to load existing cinder config file %s", CONF);
        return EXIT_FAILURE;
    }

    if(IsControl(s_eCubeRole)) {
        // user-def node groups are mapped with *-pool, respectively
        std::string customPools = HexUtilPOpen("timeout 30 ceph osd pool ls | grep -e '[-]pool' -e '[-]ssd' | tr '\n' ' '");

        curCfg["DEFAULT"]["enabled_backends"] = "ceph";
        for (int start=0,end=0; (start < (int)customPools.length()) && (end != -1); start=end+1) {
            end = customPools.find(" ", start);

            std::string pool = customPools.substr(start, end - start);

            curCfg[pool]["backend_host"] = "cube";
            curCfg[pool]["volume_backend_name"] = pool;
            curCfg[pool]["rbd_pool"] = pool;
            curCfg["DEFAULT"]["enabled_backends"] += "," + pool;
        }
    }

    WriteConfig(CONF, SB_SEC_WFMT, '=', curCfg);

    return EXIT_SUCCESS;
}

static int
ClusterStartMain(int argc, char **argv)
{
    if (argc != 1)
        return EXIT_FAILURE;

    // default volume type
    if (IsControl(s_eCubeRole)) {
        ReconfigMain(0, NULL);
        HexUtilSystemF(0, 0, HEX_SDK " os_volume_type_create CubeStorage ceph");
    }

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_cinder, RestartMain, RestartUsage);
CONFIG_COMMAND_WITH_SETTINGS(reconfig_cinder, ReconfigMain, ReconfigUsage);

CONFIG_MODULE(cinder, Init, Parse, 0, 0, Commit);
// startup sequence
CONFIG_REQUIRES(cinder, memcache);
CONFIG_REQUIRES(cinder, libvirtd);

CONFIG_MIGRATE(cinder, MAKRER_POOL);
CONFIG_MIGRATE(cinder, "/etc/cinder/cinder.d");

// extra tunings
CONFIG_OBSERVES(cinder, rabbitmq, ParseRabbitMQ, NotifyMQ);
CONFIG_OBSERVES(cinder, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(cinder, nova, ParseNova, NotifyNova);

CONFIG_TRIGGER_WITH_SETTINGS(cinder, "cluster_start", ClusterStartMain);

