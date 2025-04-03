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

// keystone config files
#define DEF_EXT     ".def"
#define CONF        "/etc/keystone/keystone.conf"

#define RETRY_FMT_H "count=1 && until "
#define RETRY_FMT_F " || (( count++ >= 5 )); do printf \"\"; done"

static const char ADMINPASS[] = "admin";
static const char DBPASS[] = "kWYg6aDBadeM6Xz3";
static const char OSCMD[] = "/usr/bin/openstack";

static const char ADMINCLI[] = "admin_cli";
static const char ADMINCLIPASS[] = "66K1ogIiRt5KnyHe";

static const char ADMIN_RC[] = "/etc/admin-openrc.sh";
static const char ADMINCLI_MARKER[] = "/etc/appliance/state/admin_cli_user_done";
static const char IDP_MARKER[] = "/etc/appliance/state/keystone_idp_done";
static const char IDP_UPDATE[] = "/etc/appliance/state/keystone_idp_update";

static const char USER[] = "keystone";
static const char GROUP[] = "keystone";
static const char FKEY_DIR[] = "/etc/keystone/fernet-keys";
static const char CKEY_DIR[] = "/etc/keystone/credential-keys";
static const char IDP_RULES[] = "/etc/keystone/idp_mapping_rules.json";

static Configs cfg;

static bool s_bSetup = true;
static bool s_bCubeModified = false;

static bool s_bScriptChanged = false;
static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bEndpointChanged = false;

static CubeRole_e s_eCubeRole;

// external global variables
CONFIG_GLOBAL_BOOL_REF(IS_MASTER);
CONFIG_GLOBAL_STR_REF(CTRL_IP);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(KEYSTONE_ENABLED, "keystone.enabled", TUNING_UNPUB, "Set to true to enable keystone.", true);
CONFIG_TUNING_STR(KEYSTONE_ADMIN_CLI_PASS, "keystone.admin.cli.password", TUNING_UNPUB, "Set keystone admin cli password.", ADMINCLIPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(KEYSTONE_DBPASS, "keystone.db.password", TUNING_UNPUB, "Set keystone database password.", DBPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(KEYSTONE_ADMIN_PASS, "keystone.admin.password", TUNING_UNPUB, "Set keystone admin token.", ADMINPASS, ValidateRegex, DFT_REGEX_STR);

// public tunigns
CONFIG_TUNING_BOOL(KEYSTONE_DEBUG, "keystone.debug.enabled", TUNING_PUB, "Set to true to enable keystone verbose log.", false);

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_REGION);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, KEYSTONE_ENABLED);
PARSE_TUNING_STR(s_dbPass, KEYSTONE_DBPASS);
PARSE_TUNING_STR(s_adminPass, KEYSTONE_ADMIN_PASS);
PARSE_TUNING_STR(s_adminCliPass, KEYSTONE_ADMIN_CLI_PASS);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 1);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);

static std::string
GetOpenstackEnv(std::string name, std::string password, std::string sharedId, std::string domain)
{
    std::string env = "";
    env += "OS_AUTH_TYPE=password ";
    env += "OS_USERNAME=" + name + " ";
    env += "OS_PASSWORD=" + password + " ";
    env += "OS_PROJECT_NAME=" + name + " ";
    env += "OS_USER_DOMAIN_NAME=" + domain + " ";
    env += "OS_PROJECT_DOMAIN_NAME=" + domain + " ";
    env += "OS_AUTH_URL=http://" + sharedId + ":5000/v3 ";
    env += "OS_IDENTITY_API_VERSION=3";

    return env;
}

// depends on mysqld (called inside commit())
static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if (!MysqlUtilIsDbExist("keystone")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE keystone") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'keystone_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'keystone_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

static bool
SetupKeystone(std::string password, std::string sharedId, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Init keystone");

    // Populate the Identity service database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"keystone-manage db_sync\" keystone");

    // Initialize Fernet key repositories
    HexUtilSystemF(0, 0, "keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone");
    HexUtilSystemF(0, 0, "keystone-manage credential_setup --keystone-user keystone --keystone-group keystone");

    // Bootstrap the Identity service
    HexUtilSystemF(0, 0, "keystone-manage bootstrap --bootstrap-password %s "
                         "--bootstrap-admin-url http://%s:5000/v3/ "
                         "--bootstrap-internal-url http://%s:5000/v3/ "
                         "--bootstrap-public-url http://%s:5000/v3/ "
                         "--bootstrap-region-id %s",
                         password.c_str(), sharedId.c_str(), sharedId.c_str(), external.c_str(), region.c_str());

    return true;
}

// should run after keystone service is running.
static bool
SetupPublicAdminUser(std::string name, std::string password, std::string sharedId, std::string domain)
{
    if (!IsControl(s_eCubeRole))
        return true;

    // Configure the administrative account
    std::string env = GetOpenstackEnv(name, password, sharedId, domain);

    // create _member_ and delete member role for backward-compatible
    HexUtilSystemF(0, 0, RETRY_FMT_H "%s %s role create _member_" RETRY_FMT_F, env.c_str(), OSCMD);
    HexUtilSystemF(0, 0, RETRY_FMT_H "%s %s role set --no-immutable member" RETRY_FMT_F, env.c_str(), OSCMD);
    HexUtilSystemF(0, 0, RETRY_FMT_H "%s %s role delete member" RETRY_FMT_F, env.c_str(), OSCMD);

    HexUtilSystemF(0, 0, RETRY_FMT_H "%s %s role add --user admin --domain %s admin" RETRY_FMT_F,
                         env.c_str(), OSCMD, domain.c_str());

    // Create a service project for each service that we add to your environment.
    HexUtilSystemF(0, 0, RETRY_FMT_H "%s %s project create --domain %s --description \"Service Project\" service" RETRY_FMT_F,
                         env.c_str(), OSCMD, domain.c_str());

    // Create a service role for other services to auth (nova, cinder)
    HexUtilSystemF(0, 0, RETRY_FMT_H "%s %s role create service" RETRY_FMT_F, env.c_str(), OSCMD);

    return true;
}

// should run after keystone service is running.
static bool
SetupInternalAdminUser(std::string name, std::string password, std::string sharedId,
                       std::string domain, std::string adminCli, std::string adminCliPass)
{
    if (!IsControl(s_eCubeRole))
        return true;

    struct stat ms;
    if (stat(ADMINCLI_MARKER, &ms) == 0)
        return true;

    // Configure the administrative account
    std::string env = GetOpenstackEnv(name, password, sharedId, domain);

    HexUtilSystemF(0, 0, RETRY_FMT_H "%s %s user create --domain %s --password %s %s" RETRY_FMT_F,
                         env.c_str(), OSCMD, domain.c_str(), adminCliPass.c_str(), adminCli.c_str());
    HexUtilSystemF(0, 0, RETRY_FMT_H "%s %s role add --project admin --user %s admin" RETRY_FMT_F,
                         env.c_str(), OSCMD, adminCli.c_str());
    HexUtilSystemF(0, 0, RETRY_FMT_H "%s %s role add --user %s --domain %s admin" RETRY_FMT_F,
                         env.c_str(), OSCMD, adminCli.c_str(), domain.c_str());

    HexUtilSystemF(0, 0, "touch %s", ADMINCLI_MARKER);

    return true;
}

// should run after keystone service is running.
static bool
SetupIdp(std::string name, std::string password, std::string sharedId, std::string domain)
{
    if (!IsControl(s_eCubeRole))
        return true;

    struct stat ms;

    if (stat(IDP_MARKER, &ms) != 0) {
        // Configure the administrative account
        std::string env = GetOpenstackEnv(name, password, sharedId, domain);

        HexUtilSystemF(0, 0, "%s %s identity provider create --domain %s --remote-id https://%s:10443/auth/realms/master cube_idp",
                             env.c_str(), OSCMD, domain.c_str(), sharedId.c_str());
        HexUtilSystemF(0, 0, "%s %s mapping create --rules %s cube_idp_mapping",
                             env.c_str(), OSCMD, IDP_RULES);
        HexUtilSystemF(0, 0, "%s %s group create cube_admins",
                             env.c_str(), OSCMD);
        HexUtilSystemF(0, 0, "%s %s role add --group cube_admins --project admin admin",
                             env.c_str(), OSCMD);
        HexUtilSystemF(0, 0, "%s %s group create cube_users",
                             env.c_str(), OSCMD);
        HexUtilSystemF(0, 0, "%s %s role add --group cube_users --project admin _member_",
                             env.c_str(), OSCMD);
        HexUtilSystemF(0, 0, "%s %s federation protocol create mapped --mapping cube_idp_mapping --identity-provider cube_idp",
                             env.c_str(), OSCMD);

        HexUtilSystemF(0, 0, HEX_SDK " os_keystone_idp_config %s", sharedId.c_str());

        HexUtilSystemF(0, 0, "touch %s", IDP_MARKER);
    }

    if (stat(IDP_UPDATE, &ms) == 0) {
        std::string env = GetOpenstackEnv(name, password, sharedId, domain);

        HexUtilSystemF(0, 0, "%s %s identity provider set --remote-id https://%s:10443/auth/realms/master cube_idp",
                             env.c_str(), OSCMD, sharedId.c_str());
        HexUtilSystemF(0, 0, HEX_SDK " os_keystone_idp_config %s", sharedId.c_str());

        unlink(IDP_UPDATE);
    }

    return true;
}

static bool
UpdateClientScript(const char* user, const char* password, const char* sharedId, const char* domain)
{
    if (IsUndef(s_eCubeRole))
        return true;

    HexLogInfo("Updating the openstack client script: %s", ADMIN_RC);

    FILE *f = fopen(ADMIN_RC, "w");
    if (!f) {
        HexLogError("failed to update client script %s", ADMIN_RC);
        return false;
    }

    fprintf(f, "export OS_AUTH_TYPE=password\n");
    fprintf(f, "export OS_USERNAME=%s\n", user);
    fprintf(f, "export OS_PASSWORD=%s\n", password);
    fprintf(f, "export OS_PROJECT_NAME=admin\n");
    fprintf(f, "export OS_USER_DOMAIN_NAME=%s\n", domain);
    fprintf(f, "export OS_PROJECT_DOMAIN_NAME=%s\n", domain);
    fprintf(f, "export OS_AUTH_URL=http://%s:5000/v3\n", sharedId);
    fprintf(f, "export OS_IDENTITY_API_VERSION=3\n");
    fprintf(f, "export OS_IMAGE_API_VERSION=2\n");

    fclose(f);

    return true;
}

static bool
UpdateDbConn(std::string sharedId, std::string password)
{
    std::string dbconn = "mysql+pymysql://keystone:";
    dbconn += password;
    dbconn += "@";
    dbconn += sharedId;
    dbconn += "/keystone";

    cfg["database"]["connection"] = dbconn;

    return true;
}

static bool
UpdateConfig(std::string sharedId)
{
    if(IsControl(s_eCubeRole)) {
        cfg["cache"]["memcache_servers"] = sharedId + ":11211";
        cfg["cache"]["enabled"] = "true";
        cfg["cache"]["backend"] = "dogpile.cache.memcached";

        cfg["token"]["provider"] = "fernet";

        // For grafana
        cfg["cors"]["allowed_origin"] = "http://" + sharedId + ":3000";

        // For idp setup
        cfg["auth"]["methods"] = "password,token,oauth1,mapped";
        cfg["federation"]["trusted_dashboard"] =
            "https://" + sharedId + "/horizon/auth/websso/\ntrusted_dashboard = https://" + sharedId + ":9999/api/openstack/skyline/api/v1/websso";
        cfg["federation"]["sso_callback_template"] = "/etc/keystone/sso_callback_template.html";
        cfg["federation"]["remote_id_attribute"] = "MELLON_IDP";

        cfg["oslo_messaging_notifications"]["driver"] = "messagingv2";
        cfg["oslo_messaging_notifications"]["transport_url"] = "kafka://" + sharedId + ":9095";
    }

    return true;
}

static bool
UpdateEndpoint(std::string password, std::string endpoint, std::string external,
               std::string domain, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating keystone endpoint");

    std::string pub = "http://" + external + ":5000/v3";
    std::string adm = "http://" + endpoint + ":5000/v3";
    std::string intr = "http://" + endpoint + ":5000/v3";

    HexUtilSystemF(0, 0, HEX_SDK " os_keystone_endpoint_update %s %s %s",
                         pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static
bool Init()
{
    if (HexMakeDir(FKEY_DIR, USER, GROUP, 0700) != 0)
        return false;

    if (HexMakeDir(CKEY_DIR, USER, GROUP, 0700) != 0)
        return false;

    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', cfg)) {
        HexLogError("failed to load keystone config file %s", CONF);
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

static void
NotifyCube(bool modified)
{
    s_bCubeModified = IsModifiedTune(1);
    s_eCubeRole = GetCubeRole(s_cubeRole);
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        s_bConfigChanged = true;
        return true;
    }

    s_bScriptChanged = s_adminPass.modified() | s_bCubeModified | G_MOD(SHARED_ID);

    s_bDbPassChanged = s_dbPass.modified() | s_bCubeModified;

    s_bConfigChanged = modified | s_bCubeModified | G_MOD(SHARED_ID) | G_MOD(MGMT_ADDR);

    s_bEndpointChanged = s_bCubeModified | G_MOD(SHARED_ID) | G_MOD(EXTERNAL);

    return s_bScriptChanged | s_bDbPassChanged |
           s_bConfigChanged | s_bEndpointChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    SetupCheck();
    if (!s_bSetup) {
        s_bScriptChanged = true;
        s_bDbPassChanged = true;
        s_bEndpointChanged = false;
    }

    bool isMaster = G(IS_MASTER);
    std::string sharedId = G(SHARED_ID);
    std::string myIp = G(MGMT_ADDR);
    std::string external = G(EXTERNAL);

    // don't scramble admin pass since it's used for logging in to LMI
    std::string adminPass = GetSaltKey(false, s_adminPass.newValue(), s_seed.newValue());
    std::string adminCliPass = GetSaltKey(s_saltkey, s_adminCliPass.newValue(), s_seed.newValue());
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());

    // 1. System Config
    if (s_bScriptChanged)
        UpdateClientScript(ADMINCLI, adminCliPass.c_str(), sharedId.c_str(), s_cubeDomain.c_str());

    if (s_bDbPassChanged && IsControl(s_eCubeRole))
        MysqlUtilUpdateDbPass(USER, dbPass.c_str());

    // 2. Service Config
    if (s_bConfigChanged) {
        UpdateConfig(sharedId);
        UpdateDbConn(sharedId, dbPass);
        HexUtilSystemF(0, 0, HEX_SDK " os_wsgi_conf_update %s", myIp.c_str());

        WriteConfig(CONF, SB_SEC_WFMT, '=', cfg);
    }

    // 3. Service Setup (service creation requires httpd running)
    if (!s_bSetup)
        SetupKeystone(adminPass, sharedId, external, s_cubeRegion.newValue());

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_keystone_db");

    // syncing fernet keys from master node
    if (!isMaster) {
        std::string peer = GetMaster(s_ha, G(CTRL_IP), s_ctrlAddrs);
        HexUtilSystemF(0, 0, "rsync root@%s:%s/* %s 2>/dev/null", peer.c_str(), FKEY_DIR, FKEY_DIR);
        HexUtilSystemF(0, 0, "chown -R %s:%s %s", USER, GROUP, FKEY_DIR);
        HexUtilSystemF(0, 0, "rsync root@%s:%s/* %s 2>/dev/null", peer.c_str(), CKEY_DIR, CKEY_DIR);
        HexUtilSystemF(0, 0, "chown -R %s:%s %s", USER, GROUP, CKEY_DIR);
    }
    else if (isMaster && access(CONTROL_REJOIN, F_OK) == 0) {
        std::string peer = GetControllerPeers(myIp, s_ctrlAddrs)[0];
        HexUtilSystemF(0, 0, "rsync root@%s:%s/* %s 2>/dev/null", peer.c_str(), FKEY_DIR, FKEY_DIR);
        HexUtilSystemF(0, 0, "chown -R %s:%s %s", USER, GROUP, FKEY_DIR);
        HexUtilSystemF(0, 0, "rsync root@%s:%s/* %s 2>/dev/null", peer.c_str(), CKEY_DIR, CKEY_DIR);
        HexUtilSystemF(0, 0, "chown -R %s:%s %s", USER, GROUP, CKEY_DIR);
    }

    // 4. keystone relies on httpd wsgi
    SystemdCommitService(IsControl(s_eCubeRole), "httpd");
    if (HexUtilSystemF(0, 0, HEX_SDK " wait_for_http_endpoint %s 5000 60", sharedId.c_str()) != 0) {
        return false;
    }

    // 5. setup an public and internal admin user
    if (!s_bSetup)
        SetupPublicAdminUser("admin", adminPass, sharedId, s_cubeDomain.newValue());

    SetupInternalAdminUser("admin", adminPass, sharedId, s_cubeDomain.newValue(), ADMINCLI, adminCliPass);

    // check for setup migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_keystone");

    // 6. create endpoint
    if (s_bEndpointChanged) {
        bool result = false;
        bool createEpSnap = (!isMaster || (isMaster && access(CONTROL_REJOIN, F_OK) == 0));

        // renew endpoint snapshot first, other control nodes may have made changes
        if (!createEpSnap || HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_snapshot_create 30") == 0)
            result = UpdateEndpoint(adminPass, sharedId, external, s_cubeDomain.newValue(), s_cubeRegion.newValue());

        if (!result) {
            // policy committing should stop here in case casuing undesired cluster settings
            HexLogError("keystone service is unavailable");
            return false;
        }
    }

    return true;
}

static bool
CommitIdp(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    std::string sharedId = G(SHARED_ID);
    std::string adminPass = GetSaltKey(false, s_adminPass.newValue(), s_seed.newValue());
    SetupIdp("admin", adminPass, sharedId, s_cubeDomain.newValue());

    return true;
}

static int
ClusterStartMain(int argc, char **argv)
{
    if (argc != 1)
        return EXIT_FAILURE;

    if (IsControl(s_eCubeRole))
        HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_snapshot_create");

    return EXIT_SUCCESS;
}

CONFIG_MODULE(keystone, Init, Parse, 0, 0, Commit);
CONFIG_MODULE(keystone_idp, 0, 0, 0, 0, CommitIdp);

// startup sequence
CONFIG_REQUIRES(keystone, rabbitmq);
CONFIG_REQUIRES(keystone, mysql);
CONFIG_REQUIRES(keystone, haproxy);

CONFIG_REQUIRES(keystone_idp, keycloak);

// extra tunings
CONFIG_OBSERVES(keystone, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(keystone, ADMINCLI_MARKER);
CONFIG_MIGRATE(keystone, ADMIN_RC);
CONFIG_MIGRATE(keystone, FKEY_DIR);
CONFIG_MIGRATE(keystone, CKEY_DIR);

CONFIG_TRIGGER_WITH_SETTINGS(keystone, "cluster_start", ClusterStartMain);

