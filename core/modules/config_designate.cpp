// CUBE

#include <unistd.h>

#include <hex/log.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <hex/logrotate.h>
#include <hex/string_util.h>

#include <cube/config_file.h>
#include <cube/cluster.h>
#include <cube/systemd_util.h>

#include "mysql_util.h"
#include "include/role_cubesys.h"

// designate config files
#define DEF_EXT     ".def"
#define CONF        "/etc/designate/designate.conf"
#define POOL_CONF   "/etc/designate/pools.yaml"

static const char USER[] = "designate";
static const char GROUP[] = "designate";

// named config
static const char NAMED_CONF_IN[] = "/etc/named.conf.in";
static const char NAMED_CONF[] = "/etc/named.conf";

// DNS config
static const char DNS_CONF[] = "/etc/resolv.conf";

// designate common
static const char RUNDIR[] = "/run/designate";
static const char LOGDIR[] = "/var/log/designate";

// dns service
static const char NAMED_NAME[] = "named";

// designate services
static const char API_NAME[] = "designate-api";
static const char CNRL_NAME[] = "designate-central";
static const char WKR_NAME[] = "designate-worker";
static const char PDR_NAME[] = "designate-producer";
static const char MDNS_NAME[] = "designate-mdns";

static const char OSCMD[] = "/usr/bin/openstack";
static const char OPENRC[] = "/etc/admin-openrc.sh";
static const char RNDC_KEY[] = "/etc/designate/rndc.key";

static const char USERPASS[] = "xxXyEb40zrur36EQ";
static const char DBPASS[] = "6hbC8ST3mmFKxrtc";

static Configs cfg;

static bool s_bSetup = true;

static bool s_bNetModified = false;
static bool s_bCubeModified = false;
static bool s_bMqModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bPoolYamlChanged = false;
static bool s_bNamedCfgChanged = false;
static bool s_bEndpointChanged = false;

static CubeRole_e s_eCubeRole;

static ConfigString s_hostname;
static ConfigString s_dns1;
static ConfigString s_dns2;
static ConfigString s_dns3;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("designate", "/var/log/designate/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_BOOL_REF(IS_MASTER);
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(DESIGNATE_ENABLED, "designate.enabled", TUNING_UNPUB, "Set to true to enable designate.", true);
CONFIG_TUNING_STR(DESIGNATE_USERPASS, "designate.user.password", TUNING_UNPUB, "Set designate user password.", USERPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(DESIGNATE_DBPASS, "designate.db.password", TUNING_UNPUB, "Set designate db password.", DBPASS, ValidateRegex, DFT_REGEX_STR);

// public tunigns
CONFIG_TUNING_BOOL(DESIGNATE_DEBUG, "designate.debug.enabled", TUNING_PUB, "Set to true to enable designate verbose log.", false);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC(NET_DNS_1ST);
CONFIG_TUNING_SPEC(NET_DNS_2ND);
CONFIG_TUNING_SPEC(NET_DNS_3RD);
CONFIG_TUNING_SPEC_STR(RABBITMQ_OPENSTACK_PASSWD);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_HOSTS);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, DESIGNATE_ENABLED);
PARSE_TUNING_BOOL(s_debug, DESIGNATE_DEBUG);
PARSE_TUNING_STR(s_userPass, DESIGNATE_USERPASS);
PARSE_TUNING_STR(s_dbPass, DESIGNATE_USERPASS);
PARSE_TUNING_X_STR(s_mqPass, RABBITMQ_OPENSTACK_PASSWD, 1);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 2);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 2);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 2);
PARSE_TUNING_X_STR(s_ctrlHosts, CUBESYS_CONTROL_HOSTS, 2);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 2);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 2);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 2);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 2);

static bool
UpdatePool()
{
    HexUtilSystemF(0, 30, "su -s /bin/sh -c \"/usr/local/bin/designate-manage pool update\" %s", USER);
    return true;
}

static bool
WritePoolConfig(const std::string &ctrlhosts, const std::string &ctrladdrs)
{
    FILE *fout = fopen(POOL_CONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s pool config: %s", USER, POOL_CONF);
        return false;
    }

    fprintf(fout, "- name: default\n");
    fprintf(fout, "  description: Default Pool\n");
    fprintf(fout, "\n");

    fprintf(fout, "  attributes: {}\n");
    fprintf(fout, "\n");

    fprintf(fout, "  ns_records:\n");
    auto hosts = hex_string_util::split(ctrlhosts, ',');
    int prio = 1;
    for (auto host : hosts) {
        fprintf(fout, "    - hostname: %s.cube.org.\n", host.c_str());
        fprintf(fout, "      priority: %d\n", prio++);
    }
    fprintf(fout, "\n");

    fprintf(fout, "  nameservers:\n");
    auto addrs = hex_string_util::split(ctrladdrs, ',');
    for (auto addr : addrs) {
        fprintf(fout, "    - host: %s\n", addr.c_str());
        fprintf(fout, "      port: 53\n");
    }
    fprintf(fout, "\n");

    fprintf(fout, "  targets:\n");

    int index = 1;
    for (auto addr : addrs) {
        fprintf(fout, "    - type: bind9\n");
        fprintf(fout, "      description: BIND9 Server %d\n", index++);

        fprintf(fout, "      masters:\n");
        for (auto addr2 : addrs) {
            fprintf(fout, "        - host: %s\n", addr2.c_str());
            fprintf(fout, "          port: 5354\n");
        }
        fprintf(fout, "\n");

        fprintf(fout, "      options:\n");
        fprintf(fout, "        host: %s\n", addr.c_str());
        fprintf(fout, "        port: 53\n");
        fprintf(fout, "        rndc_host: %s\n", addr.c_str());
        fprintf(fout, "        rndc_port: 953\n");
        fprintf(fout, "        rndc_key_file: %s\n", RNDC_KEY);
        fprintf(fout, "\n");
    }
    fprintf(fout, "\n");

    fclose(fout);

    return true;
}

static bool
WriteNamedConfTemplates(const std::string& dns1, const std::string& dns2, const std::string& dns3)
{
    std::string dns1cfg = dns1.length() ? dns1 + ";" : "";
    std::string dns2cfg = dns2.length() ? dns2 + ";" : "";
    std::string dns3cfg = dns3.length() ? dns3 + ";" : "";

    if (HexUtilSystemF(0, 0, "sed -e \"s/@DNS1@/%s/\" -e \"s/@DNS2@/%s/\" -e \"s/@DNS3@/%s/\" %s > %s",
                      dns1cfg.c_str(), dns2cfg.c_str(), dns3cfg.c_str(), NAMED_CONF_IN, NAMED_CONF) != 0) {
        HexLogError("failed to update %s", NAMED_CONF);
        return false;
    }

    return true;
}

static bool
WriteDNSConf(std::string sharedId)
{
    if (HexUtilSystemF(0, 0, "echo 'nameserver %s' >> %s",
            sharedId.c_str(), DNS_CONF) != 0) {
        HexLogError("failed to update %s", DNS_CONF);
        return false;
    }

    return true;
}

// should run after mysql services are running.
static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if(!MysqlUtilIsDbExist("designate")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE designate") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON designate.* TO 'designate'@'localhost' IDENTIFIED BY 'designate_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON designate.* TO 'designate'@'%' IDENTIFIED BY 'designate_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

// Setup should run after keystone.
static bool
SetupService(std::string domain, std::string userPass)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up designate");

    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"/usr/local/bin/designate-manage database sync\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the designate service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s designate",
                         env.c_str(), OSCMD, domain.c_str(), userPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user designate admin", env.c_str(), OSCMD);

    HexUtilSystemF(0, 0, "%s %s service create --name designate "
                         "--description \"Openstack DNS Service\" dns",
                         env.c_str(), OSCMD);

    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating designate endpoint");

    std::string pub = "http://" + external + ":9001";
    std::string adm = "http://" + endpoint + ":9001";
    std::string intr = "http://" + endpoint + ":9001";

    HexUtilSystemF(0, 0, "/usr/sbin/hex_sdk os_endpoint_update %s %s %s %s %s",
                         "dns", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static bool
UpdateDbConn(std::string sharedId, std::string password)
{
    if(IsControl(s_eCubeRole)) {
        std::string dbconn = "mysql+pymysql://designate:";
        dbconn += password;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/designate";

        cfg["storage:sqlalchemy"]["connection"] = dbconn;
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
UpdateMyIp(std::string myip)
{
    if(IsControl(s_eCubeRole)) {
        cfg["service:api"]["listen"] = myip + ":9001";
        cfg["service:api"]["api_base_uri"] = "http://" + myip + ":9001/";
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
        cfg["oslo_messaging_notifications"]["transport_url"] = "kafka://" + sharedId + ":9095";
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
UpdateCfg(bool ha, const std::string& domain, const std::string& userPass)
{
    if(IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["log_dir"] = "/var/log/designate";

        cfg["keystone_authtoken"].clear();
        cfg["keystone_authtoken"]["auth_type"] = "password";
        cfg["keystone_authtoken"]["project_domain_name"] = domain;
        cfg["keystone_authtoken"]["user_domain_name"] = domain;
        cfg["keystone_authtoken"]["project_name"] = "service";
        cfg["keystone_authtoken"]["username"] = "designate";
        cfg["keystone_authtoken"]["password"] = userPass;

        cfg["service:api"].clear();
        cfg["service:api"]["auth_strategy"] = "keystone";
        cfg["service:api"]["enable_api_v1"] = "true";
        cfg["service:api"]["enabled_extensions_v1"] = "quotas, reports";
        cfg["service:api"]["enable_api_v2"] = "true";
        cfg["service:api"]["enabled_extensions_v2"] = "quotas, reports";

        cfg["service:worker"]["enabled"] = "true";

        cfg["oslo_messaging_notifications"]["driver"] = "messagingv2";
    }

    return true;
}

static bool
CommitPreflight(bool enabled)
{
    if (IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled, API_NAME, true);     // designate-api
        SystemdCommitService(enabled, CNRL_NAME, true);    // designate-central
    }

    return true;
}

static bool
CommitService(bool enabled)
{
    if (IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled, WKR_NAME, true);     // designate-worker
        SystemdCommitService(enabled, PDR_NAME, true);     // designate-producer
        SystemdCommitService(enabled, MDNS_NAME, true);    // designate-mdns
    }

    return true;
}

static bool
Init()
{
    if (HexMakeDir(RUNDIR, USER, GROUP, 0755) != 0)
        return false;

    // load designate configurations
    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', cfg)) {
        HexLogError("failed to load designate config file %s", CONF DEF_EXT);
        return false;
    }

    return true;
}

static bool
ParseNet(const char *name, const char *value, bool isNew)
{
    if (strcmp(name, NET_HOSTNAME) == 0) {
        s_hostname.parse(value, isNew);
    }
    else if (strcmp(name, NET_DNS_1ST) == 0) {
        s_dns1.parse(value, isNew);
    }
    else if (strcmp(name, NET_DNS_2ND) == 0) {
        s_dns2.parse(value, isNew);
    }
    else if (strcmp(name, NET_DNS_3RD) == 0) {
        s_dns3.parse(value, isNew);
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
    s_bNetModified = s_hostname.modified() | s_dns1.modified() | s_dns2.modified() | s_dns3.modified();
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
CommitDnsCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        s_bNamedCfgChanged = true;
        return true;
    }

    s_bNamedCfgChanged = s_bNetModified | G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID);

    return s_bNamedCfgChanged;
}

static bool
CommitDns(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (!IsControl(s_eCubeRole) || !CommitDnsCheck(modified, dryLevel))
        return true;

    bool enabled = s_enabled;
    bool isMaster = G(IS_MASTER);
    std::string myip = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);

    if (s_bNamedCfgChanged) {
        WriteNamedConfTemplates(s_dns1, s_dns2, s_dns3);
        WriteDNSConf(sharedId);
    }

    if (access(RNDC_KEY, F_OK) != 0) {
        std::string peer;
        if (!isMaster) {
            peer = GetMaster(s_ha, myip, s_ctrlAddrs);
            HexUtilSystemF(0, 0, "scp root@%s:%s %s 2>/dev/null", peer.c_str(), RNDC_KEY, RNDC_KEY);
        }
        else if (isMaster && access(CONTROL_REJOIN, F_OK) == 0) {
            peer = GetControllerPeers(myip, s_ctrlAddrs)[0];
            HexUtilSystemF(0, 0, "scp root@%s:%s %s 2>/dev/null", peer.c_str(), RNDC_KEY, RNDC_KEY);
        }
        else {
            HexUtilSystemF(0, 0, "rndc-confgen -a -k designate -c %s", RNDC_KEY);
        }
        if(HexSetFileMode(RNDC_KEY, "named", "named", 0640) != 0) {
            HexLogWarning("Unable to set file %s mode/permission", RNDC_KEY);
        }
    }

    SystemdCommitService(enabled, NAMED_NAME, true);   // named

    return true;
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        s_bConfigChanged = true;
        s_bPoolYamlChanged = true;
        return true;
    }

    s_bDbPassChanged = s_dbPass.modified() | s_bCubeModified;

    s_bConfigChanged = modified | s_bMqModified | s_bCubeModified |
                               G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID);

    s_bPoolYamlChanged = s_bCubeModified | s_bNetModified;

    s_bEndpointChanged = s_bCubeModified | G_MOD(SHARED_ID) | G_MOD(EXTERNAL);

    return s_bDbPassChanged | s_bConfigChanged | s_bPoolYamlChanged | s_bEndpointChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (!IsControl(s_eCubeRole) || IsEdge(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = s_enabled;
    std::string myip = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    std::string userPass = GetSaltKey(s_saltkey, s_userPass, s_seed);
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass, s_seed);
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass, s_seed);

    SetupCheck();
    if (!s_bSetup) {
        s_bDbPassChanged = true;
        s_bEndpointChanged = true;
    }

    if (s_bDbPassChanged && IsControl(s_eCubeRole))
        MysqlUtilUpdateDbPass(USER, dbPass.c_str());

    if (s_bConfigChanged) {
        UpdateCfg(s_ha, s_cubeDomain, userPass);
        UpdateSharedId(sharedId);
        UpdateMyIp(myip);
        UpdateDbConn(sharedId, dbPass);
        UpdateMqConn(s_ha, sharedId, mqPass, s_ctrlAddrs.newValue());
        UpdateDebug(s_debug);

        // write back to designate config files
        WriteConfig(CONF, SB_SEC_WFMT, '=', cfg);
    }

    // Service Setup (keystone service must be running)
    if (!s_bSetup)
        SetupService(s_cubeDomain, userPass);

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_designate_db");

    if (s_bEndpointChanged)
        UpdateEndpoint(sharedId, external, s_cubeRegion);

    CommitPreflight(enabled);

    if (s_bPoolYamlChanged) {
        std::string hosts = s_ha ? s_ctrlHosts : s_hostname;
        std::string addrs = s_ha ? s_ctrlAddrs : myip;
        WritePoolConfig(hosts, addrs);
        // waiting for the readiness of preflight designate services
        sleep(15);
        UpdatePool();
    }

    CommitService(enabled);

    WriteLogRotateConf(log_conf);

    return true;
}

static void
RestartDnsUsage(void)
{
    fprintf(stderr, "Usage: %s restart_dns\n", HexLogProgramName());
}

static int
RestartDnsMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartDnsUsage();
        return EXIT_FAILURE;
    }

    bool enabled = s_enabled && IsControl(s_eCubeRole);
    SystemdCommitService(enabled, NAMED_NAME, true);

    return EXIT_SUCCESS;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_designate\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    bool enabled = s_enabled && !IsEdge(s_eCubeRole) && IsControl(s_eCubeRole);
    CommitPreflight(enabled);
    CommitService(enabled);

    return EXIT_SUCCESS;
}

static void
UpdatePoolUsage(void)
{
    fprintf(stderr, "Usage: %s update_designate_pools\n", HexLogProgramName());
}

static int
UpdatePoolMain(int argc, char* argv[])
{
    if (argc != 1) {
        UpdatePoolUsage();
        return EXIT_FAILURE;
    }

    bool enabled = s_enabled && IsControl(s_eCubeRole);
    if (enabled)
        UpdatePool();

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_dns, RestartDnsMain, RestartDnsUsage);
CONFIG_COMMAND_WITH_SETTINGS(restart_designate, RestartMain, RestartUsage);
CONFIG_COMMAND_WITH_SETTINGS(update_designate_pools, UpdatePoolMain, UpdatePoolUsage);

CONFIG_MODULE(dns, 0, 0, 0, 0, CommitDns);

// startup sequence
CONFIG_REQUIRES(dns, cube_scan);

// extra tunings
CONFIG_OBSERVES(dns, net, ParseNet, NotifyNet);

CONFIG_MIGRATE(dns, RNDC_KEY);

CONFIG_MODULE(designate, Init, Parse, 0, 0, Commit);

// startup sequence
CONFIG_REQUIRES(designate, memcache);
CONFIG_REQUIRES(designate, dns);

// extra tunings
CONFIG_OBSERVES(designate, rabbitmq, ParseRabbitMQ, NotifyMQ);
CONFIG_OBSERVES(designate, cubesys, ParseCube, NotifyCube);

