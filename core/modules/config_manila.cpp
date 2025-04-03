// CUBE

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/string_util.h>
#include <hex/dryrun.h>

#include <cube/systemd_util.h>
#include <cube/config_file.h>
#include <cube/cluster.h>

#include "mysql_util.h"
#include "include/role_cubesys.h"

// config files
#define DEF_EXT     ".def"
#define CONF        "/etc/manila/manila.conf"
#define INIT_DONE   "/etc/appliance/state/manila_init_done"

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

static Configs cfg;

static bool s_bSetup = true;
static bool s_bInit = true;

static bool s_bMqModified = false;
static bool s_bCubeModified = false;
static bool s_bKeystoneModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bEndpointChanged = false;

static CubeRole_e s_eCubeRole;

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
CONFIG_TUNING_STR(MANILA_VOLUME_TYPE, "manila.volume.type", TUNING_PUB, "Set manila backend volume type.", "CubeStorage", ValidateRegex, DFT_REGEX_STR);

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

static bool
InitCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if (access(INIT_DONE, F_OK) != 0)
        s_bInit = false;

    return true;
}

// should run after mysql services are running.
static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if(!MysqlUtilIsDbExist("manila")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE manila") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON manila.* TO 'manila'@'localhost' IDENTIFIED BY 'MANILA_DBPASS'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON manila.* TO 'manila'@'%' IDENTIFIED BY 'MANILA_DBPASS'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

// should run after keystone & mysql services are running.
static bool
SetupManila(std::string domain, std::string userPass)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up manila");

    // Populate  database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"manila-manage db sync\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the manila service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s %s",
                         env.c_str(), OSCMD, domain.c_str(), userPass.c_str(), USER);
    HexUtilSystemF(0, 0, "%s %s role add --project service --user %s admin", env.c_str(), OSCMD, USER);

    // Create the service entity
    HexUtilSystemF(0, 0, "%s %s service create --name manila "
                         "--description \"OpenStack Shared File Systems\" share",
                         env.c_str(), OSCMD);
    HexUtilSystemF(0, 0, "%s %s service create --name manilav2 "
                         "--description \"OpenStack Shared File Systems\" sharev2",
                         env.c_str(), OSCMD);

    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating manila endpoint");

    std::string pub;
    std::string adm;
    std::string intr;

    pub = "http://" + external + ":8786/v1/%\\(tenant_id\\)s";
    adm = "http://" + endpoint + ":8786/v1/%\\(tenant_id\\)s";
    intr = "http://" + endpoint + ":8786/v1/%\\(tenant_id\\)s";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "share", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    pub = "http://" + external + ":8786/v2/%\\(tenant_id\\)s";
    adm = "http://" + endpoint + ":8786/v2/%\\(tenant_id\\)s";
    intr = "http://" + endpoint + ":8786/v2/%\\(tenant_id\\)s";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "sharev2", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

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
EnableService(const bool enabled)
{
    if (IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled, API_NAME);
        SystemdCommitService(enabled, SCHEDULER_NAME);
    }

    if (IsCompute(s_eCubeRole)) {
        SystemdCommitService(enabled, SHARE_NAME);
    }

    return true;
}

static bool
Init()
{
    // fail safe for creating manila lock dir
    HexMakeDir(LOCKDIR, USER, GROUP, 0755);

    // load configurations
    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', cfg)) {
        HexLogError("failed to load manila config file %s", CONF);
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
ParseKeystone(const char *name, const char *value, bool isNew)
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
NotifyKeystone(bool modified)
{
    s_bKeystoneModified = IsModifiedTune(3);
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
            s_bKeystoneModified | G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID);

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

    std::string myip = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    std::string octet4 = hex_string_util::split(myip, '.')[3];
    std::string mgmtCidr = GetMgmtCidr(s_mgmtCidr.newValue(), 1);
    std::string manilaPass = GetSaltKey(s_saltkey, s_manilaPass.newValue(), s_seed.newValue());
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass.newValue(), s_seed.newValue());
    std::string adminCliPass = GetSaltKey(s_saltkey, s_adminCliPass.newValue(), s_seed.newValue());

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
        cfg["DEFAULT"]["debug"] = s_debug.newValue()? "true" : "false";
        cfg["DEFAULT"]["cinder_volume_type"] = s_volumeType.newValue();
        cfg["DEFAULT"]["my_ip"] = myip;
        cfg["DEFAULT"]["osapi_share_listen"] = myip;

        cfg["database"]["connection"] = "mysql+pymysql://manila:" + dbPass + "@" + sharedId + "/manila";

        cfg["keystone_authtoken"]["password"] = manilaPass.c_str();
        cfg["keystone_authtoken"]["memcached_servers"] = sharedId + ":11211";
        cfg["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";

        cfg["glance"]["url"] = "http://" + sharedId + ":9696";
        cfg["glance"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["glance"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["glance"]["memcached_servers"] = sharedId + ":11211";
        cfg["glance"]["region_name"] = s_cubeRegion.newValue();
        cfg["glance"]["password"] = adminCliPass;

        cfg["neutron"]["url"] = "http://" + sharedId + ":9696";
        cfg["neutron"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["neutron"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["neutron"]["memcached_servers"] = sharedId + ":11211";
        cfg["neutron"]["region_name"] = s_cubeRegion.newValue();
        cfg["neutron"]["password"] = adminCliPass;

        cfg["nova"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["nova"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["nova"]["memcached_servers"] = sharedId + ":11211";
        cfg["nova"]["region_name"] = s_cubeRegion.newValue();
        cfg["nova"]["password"] = adminCliPass;

        cfg["cinder"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["cinder"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["cinder"]["memcached_servers"] = sharedId + ":11211";
        cfg["cinder"]["region_name"] = s_cubeRegion.newValue();
        cfg["cinder"]["password"] = adminCliPass;

        cfg["generic"]["service_network_cidr"] = mgmtCidr;
        cfg["generic"]["service_network_division_mask"] = std::to_string(std::stoi(hex_string_util::split(mgmtCidr, '/')[1]) + 7);
        cfg["generic"]["cinder_volume_type"] = s_volumeType.newValue();

        cfg["oslo_messaging_notifications"]["driver"] = "messagingv2";
        cfg["oslo_messaging_notifications"]["transport_url"] = "kafka://" + sharedId + ":9095";

        UpdateMqConn(s_ha, sharedId, mqPass, s_ctrlAddrs.newValue());

        WriteConfig(CONF, SB_SEC_WFMT, '=', cfg);
    }

    // configuring openstack sevice
    if (!s_bSetup)
        SetupManila(s_cubeDomain.newValue(), manilaPass);

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_manila_db");

    // configuring openstack end point
    if (s_bEndpointChanged)
        UpdateEndpoint(sharedId, external, s_cubeRegion.newValue());

    // service kick off
    EnableService(s_enabled);

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

    EnableService(s_enabled);

    return EXIT_SUCCESS;
}

static int
ClusterStartMain(int argc, char **argv)
{
    if (argc != 1)
        return EXIT_FAILURE;

    bool enabled = s_enabled;
    if (!enabled)
        return EXIT_SUCCESS;

    if (IsControl(s_eCubeRole)) {
        InitCheck();
        if (!s_bInit) {
            HexUtilSystemF(0, 0, HEX_SDK " os_manila_init");
            HexSystemF(0, "touch " INIT_DONE);
        }
    }

    // post actions for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_manila_db_post");

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_manila, RestartMain, RestartUsage);

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

CONFIG_TRIGGER_WITH_SETTINGS(manila, "cluster_start", ClusterStartMain);

// manila type-create cephfsnativetype false --extra-specs vendor_name=Ceph storage_protocol=CEPHFS

// client mount command line:
// ceph-fuse -m 10.0.2.102:6789 /share/ --client-mountpoint=/volumes/_nogroup/2ec39fcc-1bc0-4ccd-80ce-ebc8a0998dbc
