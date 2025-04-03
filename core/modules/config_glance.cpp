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

static const char USER[] = "glance";
static const char GROUP[] = "glance";
static const char VOLUME[] = "glance-images";

// glance config files
#define DEF_EXT     ".def"
#define GA_CONF     "/etc/glance/glance-api.conf"

static const char GA_NAME[] = "openstack-glance-api";

static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char USERPASS[] = "0ZsvkS1bHXYsywTx";
static const char DBPASS[] = "g6CEJCNFT6ufPY22";

static const char OSCMD[] = "/usr/bin/openstack";

static const char EXPORT_SYNC[] = "/etc/cron.d/glance_export_sync";

static Configs apiCfg;

static bool s_bSetup = true;
static bool s_bCubeModified = false;
static bool s_bMqModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bEndpointChanged = false;

static CubeRole_e s_eCubeRole;

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(GLANCE_ENABLED, "glance.enabled", TUNING_UNPUB, "Set to true to enable glance.", true);
CONFIG_TUNING_STR(GLANCE_USERPASS, "glance.user.password", TUNING_UNPUB, "Set glance user password.", USERPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(GLANCE_DBPASS, "glance.db.password", TUNING_UNPUB, "Set glance database password.", DBPASS, ValidateRegex, DFT_REGEX_STR);

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

// parse tunings
PARSE_TUNING_BOOL(s_enabled, GLANCE_ENABLED);
PARSE_TUNING_STR(s_glancePass, GLANCE_USERPASS);
PARSE_TUNING_STR(s_dbPass, GLANCE_DBPASS);
PARSE_TUNING_INT(s_exportRp, GLANCE_EXPORT_RP);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 1);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);
PARSE_TUNING_X_STR(s_mqPass, RABBITMQ_OPENSTACK_PASSWD, 2);

static bool
CronGlanceExportSync(int rp)
{
    if(IsControl(s_eCubeRole)) {
        FILE *fout = fopen(EXPORT_SYNC, "w");
        if (!fout) {
            HexLogError("Unable to write %s export sync-er: %s", USER, EXPORT_SYNC);
            return false;
        }

        fprintf(fout, "*/5 * * * * root " HEX_SDK " os_glance_export_sync %d\n", rp);
        fclose(fout);

        if(HexSetFileMode(EXPORT_SYNC, "root", "root", 0644) != 0) {
            HexLogError("Unable to set file %s mode/permission", EXPORT_SYNC);
            return false;
        }
    }
    else {
        unlink(EXPORT_SYNC);
    }

    return true;
}

// depends on mysqld (called inside commit())
static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if(!MysqlUtilIsDbExist("glance")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE glance") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'glance_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'glance_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

// Setup should run after glance services are running.
static bool
SetupGlance(std::string domain, std::string password)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up glance");

    // Populate the Image service database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"glance-manage db_sync\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the glance service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s glance",
                         env.c_str(), OSCMD, domain.c_str(), password.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user glance admin", env.c_str(), OSCMD);

    // Create the service entity
    HexUtilSystemF(0, 0, "%s %s service create --name %s "
                         "--description \"OpenStack Image\" image",
                         env.c_str(), OSCMD, USER);

    // Create the glance storage
    HexUtilSystemF(0, 0, HEX_SDK " ceph_create_pool %s rbd", VOLUME);
    HexUtilSystemF(0, 0, "timeout 10 ceph osd pool set %s bulk true", VOLUME);

    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating glance endpoint");

    std::string pub = "http://" + external + ":9292";
    std::string adm = "http://" + endpoint + ":9292";
    std::string intr = "http://" + endpoint + ":9292";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "image", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static bool
UpdateMqConn(const bool ha, std::string sharedId, std::string password, std::string ctrlAddrs)
{
    if (IsControl(s_eCubeRole)) {
        std::string dbconn = RabbitMqServers(ha, sharedId, password, ctrlAddrs);
        apiCfg["DEFAULT"]["transport_url"] = dbconn;
        apiCfg["DEFAULT"]["rpc_response_timeout"] = "1200";

        if (ha) {
            apiCfg["oslo_messaging_rabbit"]["rabbit_retry_interval"] = "1";
            apiCfg["oslo_messaging_rabbit"]["rabbit_retry_backoff"] = "2";
            apiCfg["oslo_messaging_rabbit"]["amqp_durable_queues"] = "true";
            apiCfg["oslo_messaging_rabbit"]["rabbit_ha_queues"] = "true";
        }
    }

    return true;
}

static bool
UpdateDbConn(std::string sharedId, std::string password)
{
    std::string dbconn = "mysql+pymysql://glance:";
    dbconn += password;
    dbconn += "@";
    dbconn += sharedId;
    dbconn += "/glance";

    apiCfg["database"]["connection"] = dbconn;

    return true;
}

static bool
UpdateMyIp(std::string myip)
{
    apiCfg["DEFAULT"]["bind_host"] = myip;
    return true;
}

static bool
UpdateSharedId(std::string sharedId)
{
    apiCfg["keystone_authtoken"]["service_token_roles_required"] = "false";
    apiCfg["keystone_authtoken"]["service_token_roles"] = "service";
    apiCfg["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
    apiCfg["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";
    apiCfg["keystone_authtoken"]["memcached_servers "] = sharedId + ":11211";
    apiCfg["oslo_messaging_notifications"]["transport_url"] = "kafka://" + sharedId + ":9095";

    return true;
}

static bool
UpdateCfg(std::string domain, std::string password)
{
    // api default configuration

    apiCfg["database"].erase("sqlite_db");
    apiCfg["keystone_authtoken"].clear();
    apiCfg["keystone_authtoken"]["auth_type"] = "password";
    apiCfg["keystone_authtoken"]["project_domain_name"] = domain.c_str();
    apiCfg["keystone_authtoken"]["user_domain_name"] = domain.c_str();
    apiCfg["keystone_authtoken"]["project_name"] = "service";
    apiCfg["keystone_authtoken"]["username"] = "glance";
    apiCfg["keystone_authtoken"]["password"] = password.c_str();
    apiCfg["paste_deploy"]["flavor"] = "keystone";
    apiCfg["paste_deploy"]["config_file"] = "/etc/glance/glance-api-paste.ini";
    apiCfg["glance_store"]["stores"] = "rbd,http";
    apiCfg["glance_store"]["default_store"] = "rbd";
    apiCfg["glance_store"]["rbd_store_user"] = USER;
    apiCfg["glance_store"]["rbd_store_pool"] = VOLUME;
    apiCfg["glance_store"]["rbd_store_ceph_conf"] = "/etc/ceph/ceph.conf";
    apiCfg["glance_store"]["rbd_store_chunk_size"] = "8";
    apiCfg["DEFAULT"]["show_image_direct_url"] = "true";
    apiCfg["DEFAULT"]["show_multiple_locations"] = "true";
    apiCfg["DEFAULT"]["log_dir"] = "/var/log/glance";
    apiCfg["oslo_messaging_notifications"]["driver"] = "messagingv2";

    if (IsControl(s_eCubeRole)) {
        std::string workers = std::to_string(GetControlWorkers(IsConverged(s_eCubeRole), IsEdge(s_eCubeRole)));
        apiCfg["DEFAULT"]["workers"] = workers;
    }

    return true;
}

static bool
Init()
{
    if (!LoadConfig(GA_CONF DEF_EXT, SB_SEC_RFMT, '=', apiCfg)) {
        HexLogError("failed to load glance api config file %s", GA_CONF);
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
ParseCube(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 1);
    return true;
}

static bool
ParseRabbitMQ(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 2);
    return true;
}

static void
NotifyCube(bool modified)
{
    s_bCubeModified = IsModifiedTune(1);
    s_eCubeRole = GetCubeRole(s_cubeRole);
}

static void
NotifyMQ(bool modified)
{
    s_bMqModified = IsModifiedTune(2);
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

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = IsControl(s_eCubeRole) && s_enabled;
    std::string myip = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    std::string glancePass = GetSaltKey(s_saltkey, s_glancePass.newValue(), s_seed.newValue());
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass.newValue(), s_seed.newValue());

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
        UpdateCfg(s_cubeDomain.newValue(), glancePass);
        UpdateSharedId(sharedId);
        UpdateMyIp(myip);
        UpdateDbConn(sharedId, dbPass);
        UpdateMqConn(s_ha, sharedId, mqPass, s_ctrlAddrs.newValue());

        // write back to glance config files
        WriteConfig(GA_CONF, SB_SEC_WFMT, '=', apiCfg);
        CronGlanceExportSync(s_exportRp);
    }

    // 3. Service Setup
    if (!s_bSetup)
        SetupGlance(s_cubeDomain.newValue(), glancePass);

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_glance_db");

    if (s_bEndpointChanged)
        UpdateEndpoint(sharedId, external, s_cubeRegion.newValue());

    // 4. Service kickoff
    SystemdCommitService(enabled, GA_NAME, true);

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

    bool enabled = IsControl(s_eCubeRole) && s_enabled;
    SystemdCommitService(enabled, GA_NAME, true);

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_glance, RestartMain, RestartUsage);

CONFIG_MODULE(glance, Init, Parse, 0, 0, Commit);
// startup sequence
CONFIG_REQUIRES(glance, memcache);
// extra tunings
CONFIG_OBSERVES(glance, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(glance, rabbitmq, ParseRabbitMQ, NotifyMQ);

