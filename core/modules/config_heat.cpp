// CUBE SDK

#include <hex/log.h>
#include <hex/logrotate.h>
#include <hex/pidfile.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>

#include <cube/systemd_util.h>
#include <cube/config_file.h>
#include <cluster.hpp>
#include <constant.hpp>

#include "mysql_util.h"
#include "include/role_cubesys.h"

static LogRotateConf log_conf("heat", "/var/log/heat/*.log", DAILY, 128, 0, true);

static const char USER[] = "heat";
static const char GROUP[] = "heat";

// heat config files
#define DEF_EXT     ".def"
#define CONF        "/etc/heat/heat.conf"

// heat common
static const char RUNDIR[] = "/run/heat";
static const char LOGDIR[] = "/var/log/heat";

static const char API_NAME[] = "openstack-heat-api";
static const char CFN_NAME[] = "openstack-heat-api-cfn";
static const char NGN_NAME[] = "openstack-heat-engine";

static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char USERPASS[] = "SVgOEffYgYu63rvR";
static const char ADMPASS[] = "Qwte0o3CwfMwSlFC";
static const char DBPASS[] = "nLgOGI6TUHpLbXqW";

static Configs cfg;

static bool s_bSetup = true;

static bool s_bMqModified = false;
static bool s_bCubeModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bEndpointChanged = false;

static CubeRole_e s_eCubeRole;

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(HEAT_ENABLED, "heat.enabled", TUNING_UNPUB, "Set to true to enable heat.", true);
CONFIG_TUNING_STR(HEAT_USERPASS, "heat.user.password", TUNING_UNPUB, "Set heat user password.", USERPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(HEAT_ADMINPASS, "heat.admin.password", TUNING_UNPUB, "Set heat domain admin password.", ADMPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(HEAT_DBPASS, "heat.db.password", TUNING_UNPUB, "Set heat database password.", DBPASS, ValidateRegex, DFT_REGEX_STR);

// public tunigns
CONFIG_TUNING_BOOL(HEAT_DEBUG, "heat.debug.enabled", TUNING_PUB, "Set to true to enable heat verbose log.", false);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(RABBITMQ_OPENSTACK_PASSWD);
CONFIG_TUNING_SPEC_BOOL(RABBITMQ_SSL_ENABLED);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_REGION);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, HEAT_ENABLED);
PARSE_TUNING_BOOL(s_debug, HEAT_DEBUG);
PARSE_TUNING_STR(s_userPass, HEAT_USERPASS);
PARSE_TUNING_STR(s_adminPass, HEAT_ADMINPASS);
PARSE_TUNING_STR(s_dbPass, HEAT_DBPASS);
PARSE_TUNING_X_STR(s_mqPass, RABBITMQ_OPENSTACK_PASSWD, 1);
PARSE_TUNING_X_BOOL(s_mqSsl, RABBITMQ_SSL_ENABLED, 1);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 2);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 2);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 2);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 2);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 2);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 2);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 2);

// depends on mysqld (called inside commit())
static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if(!MysqlUtilIsDbExist("heat")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE heat") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'localhost' IDENTIFIED BY 'heat_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'%' IDENTIFIED BY 'heat_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

// Setup should run after keystone & heat services are running.
static bool
SetupHeat(std::string domain, std::string userPass, std::string adminPass)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up heat");

    // Populate the heat service database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"/usr/bin/heat-manage db_sync\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the heat service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s heat",
                         env.c_str(), OPENSTACK_CLI, domain.c_str(), userPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user heat admin", env.c_str(), OPENSTACK_CLI);
    HexUtilSystemF(0, 0, "%s %s role add --project service --user heat service", env.c_str(), OPENSTACK_CLI);

    // Create the service entity
    HexUtilSystemF(0, 0, "%s %s service create --name heat "
                         "--description \"Orchestration\" orchestration",
                         env.c_str(), OPENSTACK_CLI);

    // Create the service entity
    HexUtilSystemF(0, 0, "%s %s service create --name heat-cfn "
                         "--description \"Orchestration\" cloudformation",
                         env.c_str(), OPENSTACK_CLI);

    // heat specific domain, roles, and admin
    HexUtilSystemF(0, 0, "%s %s domain create --description \"Stack projects and users\" heat",
                         env.c_str(), OPENSTACK_CLI);

    HexUtilSystemF(0, 0, "%s %s user create --domain heat --password %s heat_domain_admin",
                         env.c_str(), OPENSTACK_CLI, adminPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --domain heat --user-domain heat --user heat_domain_admin admin", env.c_str(), OPENSTACK_CLI);
    HexUtilSystemF(0, 0, "%s %s role create heat_stack_owner", env.c_str(), OPENSTACK_CLI);
    HexUtilSystemF(0, 0, "%s %s role create heat_stack_user", env.c_str(), OPENSTACK_CLI);

    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating heat endpoint");

    std::string pub = "http://" + external + ":8004/v1/%\\(tenant_id\\)s";
    std::string adm = "http://" + endpoint + ":8004/v1/%\\(tenant_id\\)s";
    std::string intr = "http://" + endpoint + ":8004/v1/%\\(tenant_id\\)s";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "orchestration", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    pub = "http://" + external + ":8000/v1";
    adm = "http://" + endpoint + ":8000/v1";
    intr = "http://" + endpoint + ":8000/v1";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "cloudformation", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static bool
UpdateDbConn(std::string sharedId, std::string password)
{
    if(IsControl(s_eCubeRole)) {
        std::string dbconn = "mysql+pymysql://heat:";
        dbconn += password;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/heat";

        cfg["database"]["connection"] = dbconn;
        cfg["database"]["mysql_wsrep_sync_wait"] = "1";
    }

    return true;
}

static bool
UpdateMyIp(std::string myip)
{
    if(IsControl(s_eCubeRole)) {
        cfg["heat_api"]["bind_host"] = myip;
        cfg["heat_api_cfn"]["bind_host"] = myip;
        cfg["DEFAULT"]["heat_metadata_server_url"] = "http://" + myip + ":8000";
        cfg["DEFAULT"]["heat_waitcondition_server_url"] = "http://" + myip + ":8000/v1/waitcondition";
    }

    return true;
}

static bool
UpdateSharedId(std::string sharedId)
{
    if(IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["heat_metadata_server_url"] = "http://" + sharedId + ":8000";
        cfg["DEFAULT"]["heat_waitcondition_server_url"] = "http://" + sharedId + ":8000/v1/waitcondition";
        cfg["keystone_authtoken"]["memcached_servers"] = sharedId + ":11211";
        cfg["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["keystone_authtoken"]["http_connect_timeout"] = "15";
        cfg["trustee"]["auth_url"] = "http://" + sharedId + ":5000";
        // auth_uri, not www_authenticate_uri: that name belongs to
        // keystonemiddleware and exists only in [keystone_authtoken] above.
        // [clients_keystone] is heat's own group, from heat.common.config, and
        // calls the option auth_uri. oslo.config drops an unknown key in a
        // registered group without a word, so the line used to be inert. It is
        // what heat's own keystone client resolves from; unset it fell back to
        // the unversioned [keystone_authtoken] URL. Set, heat runs version
        // discovery against it and gets http://<id>:5000/v3/. Keep it
        // unversioned: the option documents itself as "Unversioned keystone
        // url", and discovery appends the version.
        cfg["clients_keystone"]["auth_uri"] = "http://" + sharedId + ":5000";
        // [ec2authtoken] is where heat-api-cfn checks AWS-signed requests
        // against keystone's POST /v3/ec2tokens. Those are the pre-signed URLs
        // that heat_metadata_server_url and heat_waitcondition_server_url above
        // hand to guests, so this is the path every
        // AWS::CloudFormation::WaitCondition signal takes. keystone 27.1.0
        // carries the OSSA-2025-002 fix, which puts that API behind
        // rule:service_or_admin, so the call has to authenticate. heat 24.1.1's
        // middleware loads a keystoneauth plugin, session and adapter from this
        // group; UpdateCfg() gives it heat's own service credentials. Without
        // them it falls back to an anonymous POST to [ec2authtoken] auth_uri,
        // which keystone answers with a 401 and the guest sees as a 403
        // AccessDenied. auth_uri is therefore no longer written: once the
        // credentials are present, nothing reads it.
        //
        // endpoint_override is not optional. The middleware appends
        // /v3/ec2tokens to the adapter's endpoint verbatim. Without an override
        // that endpoint is the identity catalog's, which config_keystone.cpp
        // registers with /v3 already, so the call would go to
        // .../v3/v3/ec2tokens and 404.
        cfg["ec2authtoken"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["ec2authtoken"]["endpoint_override"] = "http://" + sharedId + ":5000";
        cfg["oslo_messaging_notifications"]["transport_url"] = "kafka://" + sharedId + ":9095";
    }

    return true;
}

static bool
UpdateMqConn(const bool ha, std::string sharedId, std::string password, std::string ctrlAddrs)
{
    if (IsControl(s_eCubeRole)) {
        SetMqClientConfig(cfg, ha, sharedId, password, ctrlAddrs, s_mqSsl.newValue());
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
UpdateCfg(std::string domain, std::string region, std::string userPass, std::string adminPass)
{
    if(IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["log_dir"] = LOGDIR;

        cfg["DEFAULT"]["stack_domain_admin_password"] = adminPass.c_str();
        cfg["DEFAULT"]["stack_domain_admin"] = "heat_domain_admin";
        cfg["DEFAULT"]["stack_user_domain_name"] = "heat";
        cfg["DEFAULT"]["engine_life_check_timeout"] = "30";

        cfg["keystone_authtoken"]["auth_type"] = "password";
        cfg["keystone_authtoken"]["project_domain_name"] = domain.c_str();
        cfg["keystone_authtoken"]["user_domain_name"] = domain.c_str();
        cfg["keystone_authtoken"]["project_name"] = "service";
        cfg["keystone_authtoken"]["username"] = "heat";
        cfg["keystone_authtoken"]["password"] = userPass.c_str();
        cfg["keystone_authtoken"]["service_token_roles_required"] = "true";

        cfg["trustee"]["auth_type"] = "password";
        cfg["trustee"]["user_domain_name"] = domain.c_str();
        cfg["trustee"]["username"] = "heat";
        cfg["trustee"]["password"] = userPass.c_str();

        // keystone serves POST /v3/ec2tokens only to a service or admin token;
        // see UpdateSharedId(). heat holds both roles on project service.
        cfg["ec2authtoken"]["auth_type"] = "password";
        cfg["ec2authtoken"]["project_domain_name"] = domain.c_str();
        cfg["ec2authtoken"]["user_domain_name"] = domain.c_str();
        cfg["ec2authtoken"]["project_name"] = "service";
        cfg["ec2authtoken"]["username"] = "heat";
        cfg["ec2authtoken"]["password"] = userPass.c_str();

        cfg["oslo_messaging_notifications"]["driver"] = "messagingv2";
    }

    if (IsControl(s_eCubeRole)) {
        std::string workers = std::to_string(GetControlWorkers(IsConverged(s_eCubeRole), IsEdge(s_eCubeRole)));
        cfg["DEFAULT"]["num_engine_workers"] = workers;
        cfg["heat_api"]["workers"] = workers;
        cfg["heat_api_cfn"]["workers"] = workers;
    }

    return true;
}

static bool
HeatService(bool enabled)
{
    if(IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled , API_NAME, true);     // heat-api
        SystemdCommitService(enabled , CFN_NAME, true);     // heat-api-cfn
        SystemdCommitService(enabled , NGN_NAME, true);     // heat-engine
    }

    return true;
}

static bool
Init()
{
    if (HexMakeDir(RUNDIR, USER, GROUP, 0755) != 0)
        return false;

    // load heat configurations
    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', cfg)) {
        HexLogError("failed to load heat config file %s", CONF);
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

    std::string myip = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    std::string userPass = GetSaltKey(s_saltkey, s_userPass.newValue(), s_seed.newValue());
    std::string adminPass = GetSaltKey(s_saltkey, s_adminPass.newValue(), s_seed.newValue());
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
        UpdateCfg(s_cubeDomain.newValue(), s_cubeRegion.newValue(), userPass, adminPass);
        UpdateSharedId(sharedId);
        UpdateMyIp(myip);
        UpdateDbConn(sharedId, dbPass);
        UpdateMqConn(s_ha, sharedId, mqPass, s_ctrlAddrs.newValue());
        UpdateDebug(s_debug.newValue());

        // write back to heat config files
        WriteConfig(CONF, SB_SEC_WFMT, '=', cfg);
    }

    // 3. Service Setup (service must be running)
    if (!s_bSetup)
        SetupHeat(s_cubeDomain.newValue(), userPass, adminPass);

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_heat_db");

    if (s_bEndpointChanged)
        UpdateEndpoint(sharedId, external, s_cubeRegion.newValue());

    // 4. Service kickoff
    WriteLogRotateConf(log_conf);
    HeatService(s_enabled);

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_heat\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    HeatService(s_enabled);

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_heat, RestartMain, RestartUsage);

CONFIG_MODULE(heat, Init, Parse, 0, 0, Commit);
// startup sequence
CONFIG_REQUIRES(heat, memcache);
CONFIG_REQUIRES(heat, rabbitmq);

// extra tunings
CONFIG_OBSERVES(heat, rabbitmq, ParseRabbitMQ, NotifyMQ);
CONFIG_OBSERVES(heat, cubesys, ParseCube, NotifyCube);

