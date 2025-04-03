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

// octavia config files
#define CERT_DIR    "/etc/octavia/certs/"
#define DEF_EXT     ".def"
#define CONF        "/etc/octavia/octavia.conf"
#define INIT_DONE   "/etc/appliance/state/octavia_init_done"

static const char USER[] = "octavia";
static const char GROUP[] = "octavia";

// octavia common
static const char RUNDIR[] = "/run/octavia";
static const char LOGDIR[] = "/var/log/octavia";
static const char CAFILE[] = "/etc/octavia/certs/ca_01.pem";
static const char KEYFILE[] = "/etc/octavia/octavia_ssh_key";
static const char KEYFILE_PUB[] = "/etc/octavia/octavia_ssh_key.pub";
static const char INIT_SYNC[] = "/etc/cron.d/octavia_init_sync";
static const char HMGR_SYNC[] = "/etc/cron.d/octavia_hmgr_sync";

// octavia services
static const char API_NAME[] = "octavia-api";
static const char WRKR_NAME[] = "octavia-worker";
static const char HMGR_NAME[] = "octavia-health-manager";
static const char HSKP_NAME[] = "octavia-housekeeping";

static const char OSCMD[] = "/usr/bin/openstack";
static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char USERPASS[] = "t4vYsP1IEW6O6PRo";
static const char DBPASS[] = "jUzdXiVUWmvwpcRb";

static Configs cfg;
static Configs oldCfg;

static bool s_bSetup = true;
static bool s_bInit = true;

static bool s_bCubeModified = false;
static bool s_bMqModified = false;
static bool s_bKeystoneModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bEndpointChanged = false;

static CubeRole_e s_eCubeRole;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("openstack-octavia", "/var/log/octavia/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_BOOL_REF(IS_MASTER);
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(CTRL_IP);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(OCTAVIA_ENABLED, "octavia.enabled", TUNING_UNPUB, "Set to true to enable octavia.", true);
CONFIG_TUNING_STR(OCTAVIA_USERPASS, "octavia.user.password", TUNING_UNPUB, "Set octavia user password.", USERPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(OCTAVIA_DBPASS, "octavia.db.password", TUNING_UNPUB, "Set octavia db password.", DBPASS, ValidateRegex, DFT_REGEX_STR);

// public tunigns
CONFIG_TUNING_BOOL(OCTAVIA_DEBUG, "octavia.debug.enabled", TUNING_PUB, "Set to true to enable octavia verbose log.", false);
CONFIG_TUNING_BOOL(OCTAVIA_HA, "octavia.ha", TUNING_PUB, "Set to true to enable octavia instance ha.", false);

// using external tunings
CONFIG_TUNING_SPEC_STR(RABBITMQ_OPENSTACK_PASSWD);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_STR(CUBESYS_MGMT_CIDR);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(KEYSTONE_ADMIN_CLI_PASS);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, OCTAVIA_ENABLED);
PARSE_TUNING_BOOL(s_debug, OCTAVIA_DEBUG);
PARSE_TUNING_BOOL(s_lbHa, OCTAVIA_HA);
PARSE_TUNING_STR(s_userPass, OCTAVIA_USERPASS);
PARSE_TUNING_STR(s_dbPass, OCTAVIA_USERPASS);
PARSE_TUNING_X_STR(s_mqPass, RABBITMQ_OPENSTACK_PASSWD, 1);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 2);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 2);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 2);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 2);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 2);
PARSE_TUNING_X_STR(s_mgmtCidr, CUBESYS_MGMT_CIDR, 2);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 2);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 2);
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

    if(!MysqlUtilIsDbExist("octavia")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE octavia") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON octavia.* TO 'octavia'@'localhost' IDENTIFIED BY 'octavia_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON octavia.* TO 'octavia'@'%' IDENTIFIED BY 'octavia_dbpass'")) {
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

    HexLogInfo("Setting up octavia");

    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"octavia-db-manage upgrade head\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the octavia service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s octavia",
                         env.c_str(), OSCMD, domain.c_str(), userPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user octavia admin", env.c_str(), OSCMD);

    HexUtilSystemF(0, 0, "%s %s service create --name octavia "
                         "--description \"Openstack Load Balance Service\" load-balancer",
                         env.c_str(), OSCMD);

    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating octavia endpoint");

    std::string pub = "http://" + external + ":9876";
    std::string adm = "http://" + endpoint + ":9876";
    std::string intr = "http://" + endpoint + ":9876";

    HexUtilSystemF(0, 0, "/usr/sbin/hex_sdk os_endpoint_update %s %s %s %s %s",
                         "load-balancer", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static bool
UpdateDbConn(std::string sharedId, std::string password)
{
    if(IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) {
        std::string dbconn = "mysql+pymysql://octavia:";
        dbconn += password;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/octavia";

        cfg["database"]["connection"] = dbconn;
    }

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
UpdateMyIp(std::string myip)
{
    if(IsControl(s_eCubeRole)) {
        cfg["api_settings"]["bind_host"] = myip;
    }

    return true;
}

static bool
UpdateSharedId(std::string sharedId)
{
    if(IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) {
        cfg["keystone_authtoken"]["memcached_servers"] = sharedId + ":11211";
        cfg["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";
        cfg["service_auth"]["memcached_servers"] = sharedId + ":11211";
        cfg["service_auth"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        cfg["service_auth"]["auth_url"] = "http://" + sharedId + ":5000";
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
UpdateCfg(bool ha, const std::string& domain, const std::string& userPass, const std::string& adminCliPass, const std::string& octet4)
{
    if(IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) {
        cfg["DEFAULT"]["log_dir"] = "/var/log/octavia";

        cfg["keystone_authtoken"].clear();
        cfg["keystone_authtoken"]["auth_type"] = "password";
        cfg["keystone_authtoken"]["project_domain_name"] = domain;
        cfg["keystone_authtoken"]["user_domain_name"] = domain;
        cfg["keystone_authtoken"]["project_name"] = "service";
        cfg["keystone_authtoken"]["username"] = "octavia";
        cfg["keystone_authtoken"]["password"] = userPass;

        cfg["service_auth"].clear();
        cfg["service_auth"]["auth_type"] = "password";
        cfg["service_auth"]["project_domain_name"] = domain;
        cfg["service_auth"]["user_domain_name"] = domain;
        cfg["service_auth"]["project_name"] = "admin";
        cfg["service_auth"]["username"] = "admin_cli";
        cfg["service_auth"]["password"] = adminCliPass;

        cfg["health_manager"]["heartbeat_key"] = "insecure";
        cfg["health_manager"]["bind_port"] = "5555";
        cfg["health_manager"]["bind_ip"] = "172.16.0." + octet4;
        cfg["health_manager"]["controller_ip_port_list"] = "172.16.0." + octet4 + ":5555";

        cfg["certificates"]["ca_certificate"] = std::string(CAFILE);
        cfg["certificates"]["ca_private_key"] = "/etc/octavia/certs/private/cakey.pem";
        cfg["certificates"]["ca_private_key_passphrase"] = "Cube0s!";

        cfg["haproxy_amphora"]["server_ca"] = std::string(CAFILE);
        cfg["haproxy_amphora"]["client_cert"] = "/etc/octavia/certs/client.pem";
        cfg["haproxy_amphora"]["base_path"] = "/var/lib/octavia";
        cfg["haproxy_amphora"]["base_cert_dir"] = "/var/lib/octavia/certs";
        cfg["haproxy_amphora"]["connection_max_retries"] = "360";
        cfg["haproxy_amphora"]["connection_retry_interval"] = "1";
        cfg["haproxy_amphora"]["rest_request_conn_timeout"] = "10";
        cfg["haproxy_amphora"]["rest_request_read_timeout"] = "120";

        cfg["controller_worker"]["workers"] = "2";
        cfg["controller_worker"]["amp_image_tag"] = "amphora";
        cfg["controller_worker"]["amp_flavor_id"] = "16443";
        cfg["controller_worker"]["amp_ssh_key_name"] = "octavia_ssh_key";
        cfg["controller_worker"]["network_driver"] = "allowed_address_pairs_driver";
        cfg["controller_worker"]["compute_driver"] = "compute_nova_driver";
        cfg["controller_worker"]["amphora_driver"] = "amphora_haproxy_rest_driver";
        cfg["controller_worker"]["loadbalancer_topology"] = ha ? "ACTIVE_STANDBY" : "SINGLE";

        if (s_bInit) {
            cfg["controller_worker"]["amp_boot_network_list"] = oldCfg["controller_worker"]["amp_boot_network_list"];
            cfg["controller_worker"]["amp_secgroup_list"] = oldCfg["controller_worker"]["amp_secgroup_list"];
        }
        else {
            cfg["controller_worker"]["amp_boot_network_list"] = "";
            cfg["controller_worker"]["amp_secgroup_list"] = "";
        }

        cfg["oslo_messaging"]["topic"] = "octavia_prov";

        cfg["oslo_messaging_notifications"]["driver"] = "messagingv2";
    }

    return true;
}

// static bool
// CronOctaviaSync(const std::string &cidrIp, const std::string &cidr)
// {
//     if(IsControl(s_eCubeRole)) {
//         FILE *fout = fopen(INIT_SYNC, "w");
//         if (!fout) {
//             HexLogError("Unable to write %s octavia init sync-er: %s", USER, INIT_SYNC);
//             return false;
//         }

//         fprintf(fout, "*/5 * * * * root " HEX_SDK " os_octavia_init %s\n", cidr.c_str());
//         fclose(fout);

//         if(HexSetFileMode(INIT_SYNC, "root", "root", 0644) != 0) {
//             HexLogError("Unable to set file %s mode/permission", INIT_SYNC);
//             return false;
//         }
//     }
//     else {
//         unlink(INIT_SYNC);
//     }

//     if(IsCompute(s_eCubeRole)) {
//         FILE *fout = fopen(HMGR_SYNC, "w");
//         if (!fout) {
//             HexLogError("Unable to write %s health manager sync-er: %s", USER, HMGR_SYNC);
//             return false;
//         }

//         fprintf(fout, "*/5 * * * * root " HEX_SDK " os_octavia_node_init %s %s\n", cidrIp.c_str(), cidr.c_str());
//         fclose(fout);

//         if(HexSetFileMode(HMGR_SYNC, "root", "root", 0644) != 0) {
//             HexLogError("Unable to set file %s mode/permission", HMGR_SYNC);
//             return false;
//         }
//     }
//     else {
//         unlink(HMGR_SYNC);
//     }

//     return true;
// }

static bool
CommitService(bool enabled)
{
    if (IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled, API_NAME, true);     // octavia-api
        SystemdCommitService(enabled, HSKP_NAME, true);    // octavia-housekeeping
    }

    if (IsCompute(s_eCubeRole)) {
        SystemdCommitService(enabled, WRKR_NAME, true);    // octavia-worker
        SystemdCommitService(enabled, HMGR_NAME, true);    // octavia-health-manager
    }

    return true;
}

static bool
Init()
{
    if (HexMakeDir(RUNDIR, USER, GROUP, 0755) != 0)
        return false;

    // load octavia configurations
    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', cfg)) {
        HexLogError("failed to load octavia config file %s", CONF DEF_EXT);
        return false;
    }

    // load current octavia configurations for restoration
    if (access(CONF, F_OK) == 0) {
        if (!LoadConfig(CONF, SB_SEC_RFMT, '=', oldCfg)) {
            HexLogError("failed to load existing octavia config file %s", CONF);
            return false;
        }
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
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        s_bConfigChanged = true;
        return true;
    }

    s_bDbPassChanged = s_dbPass.modified() | s_bCubeModified;

    s_bConfigChanged = modified | s_bMqModified | s_bCubeModified | s_bKeystoneModified |
               G_MOD(IS_MASTER) | G_MOD(MGMT_ADDR) | G_MOD(CTRL_IP) | G_MOD(SHARED_ID);

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

    bool enabled = s_enabled;
    bool isMaster = G(IS_MASTER);
    std::string myip = G(MGMT_ADDR);
    std::string ctrlIp = G(CTRL_IP);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);
    std::string octet4 = hex_string_util::split(myip, '.')[3];
    // maps the 4th octet ranges from 1~9 to 11~19 for avoiding conflict with dhcp port
    if (octet4.length() == 1)
        octet4 = "1" + octet4;

    std::string cidrIp = GetMgmtCidrIp(s_mgmtCidr.newValue(), 0, octet4);
    std::string cidr = GetMgmtCidr(s_mgmtCidr.newValue(), 0);
    // read mgmt cidr from vip if this is a compute-only node
    if (!IsControl(s_eCubeRole) && IsCompute(s_eCubeRole)) {
        cidrIp = HexUtilPOpen("ssh root@%s " HEX_CFG " get_octavia_cidr_ip %s 2>/dev/null", sharedId.c_str(), octet4.c_str());
        cidr = HexUtilPOpen("ssh root@%s " HEX_CFG " get_octavia_cidr 2>/dev/null", sharedId.c_str());
    }

    std::string userPass = GetSaltKey(s_saltkey, s_userPass, s_seed);
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass, s_seed);
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass, s_seed);
    std::string adminCliPass = GetSaltKey(s_saltkey, s_adminCliPass.newValue(), s_seed.newValue());

    InitCheck();
    SetupCheck();
    if (!s_bSetup) {
        s_bDbPassChanged = true;
        s_bEndpointChanged = true;
    }

    if (s_bDbPassChanged && IsControl(s_eCubeRole))
        MysqlUtilUpdateDbPass(USER, dbPass.c_str());

    if (s_bConfigChanged) {
        UpdateCfg(s_lbHa, s_cubeDomain, userPass, adminCliPass, octet4);
        UpdateSharedId(sharedId);
        UpdateMyIp(myip);
        UpdateDbConn(sharedId, dbPass);
        UpdateMqConn(s_ha, sharedId, mqPass, s_ctrlAddrs.newValue());
        UpdateDebug(s_debug);

        // write back to octavia config files
        WriteConfig(CONF, SB_SEC_WFMT, '=', cfg);
    }

    // Service Setup (keystone service must be running)
    if (!s_bSetup)
        SetupService(s_cubeDomain, userPass);

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_octavia_db");

    if (s_bEndpointChanged)
        UpdateEndpoint(sharedId, external, s_cubeRegion);

    // Service kickoff
    CommitService(enabled);

    WriteLogRotateConf(log_conf);

    if(access(KEYFILE, F_OK) != 0) {
        // https://github.com/cornfeedhobo/ssh-keydgen
        HexUtilSystemF(0, 0, "echo octavia-%s | /usr/sbin/ssh-keydgen -t rsa -f %s", s_seed.c_str(), KEYFILE);
        HexSetFileMode(KEYFILE, "root", "root", 0600);
        HexSetFileMode(KEYFILE_PUB, "root", "root", 0600);
    }

    if (access(CAFILE, F_OK) != 0) {
        if (isMaster && access(CONTROL_REJOIN, F_OK) != 0) {
            HexUtilSystemF(0, 0, "/etc/octavia/create_certificates.sh %s /etc/octavia/octavia-certs.cnf", CERT_DIR);
        }
        else {
            std::string peer = s_ha ? GetControllerPeers(myip, s_ctrlAddrs)[0] : ctrlIp;
            HexUtilSystemF(0, 0, "scp -r root@%s:%s %s", peer.c_str(), CERT_DIR, CERT_DIR);
        }
        HexSystemF(0, "chmod -R 755 %s", CERT_DIR);
    }

    // CronOctaviaSync(cidrIp, cidr);

    return true;
}

static void
GetMgmtCidrIpUsage(void)
{
    fprintf(stderr, "Usage: %s get_octavia_cidr_ip <octet4>\n", HexLogProgramName());
}

static int
GetMgmtCidrIpMain(int argc, char* argv[])
{
    if (argc != 2 /* [0]="get_octavia_cidr_ip", [1]="octet4" */) {
        GetMgmtCidrIpUsage();
        return EXIT_FAILURE;
    }

    if (IsControl(s_eCubeRole)) {
        std::string cidr = GetMgmtCidr(s_mgmtCidr.newValue(), 0);
        std::string cidrIp = GetMgmtCidrIp(s_mgmtCidr.newValue(), 0, std::string(argv[1]));
        printf("%s", cidrIp.c_str());
    }

    return EXIT_SUCCESS;
}

static void
GetMgmtCidrUsage(void)
{
    fprintf(stderr, "Usage: %s get_octavia_cidr \n", HexLogProgramName());
}

static int
GetMgmtCidrMain(int argc, char* argv[])
{
    if (argc > 1 /* [0]="get_octavia_cidr" */) {
        GetMgmtCidrUsage();
        return EXIT_FAILURE;
    }

    if (IsControl(s_eCubeRole)) {
        std::string cidr = GetMgmtCidr(s_mgmtCidr.newValue(), 0);
        printf("%s", cidr.c_str());
    }

    return EXIT_SUCCESS;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_octavia\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    bool enabled = s_enabled;
    CommitService(enabled);

    return EXIT_SUCCESS;
}

static void
ReconfigUsage(void)
{
    fprintf(stderr, "Usage: %s reconfig_octavia \n", HexLogProgramName());
}

static int
ReconfigMain(int argc, char* argv[])
{
    if (argc > 3 /* [0]="reconfig_octavia", [1]=<network_id>, [2]=<sec_grp_id> */) {
        ReconfigUsage();
        return EXIT_FAILURE;
    }

    bool enabled = s_enabled;
    if (!enabled)
        return EXIT_SUCCESS;

    static Configs curCfg;
    if (!LoadConfig(CONF, SB_SEC_RFMT, '=', curCfg)) {
        HexLogError("failed to load existing octavia config file %s", CONF);
        return EXIT_FAILURE;
    }

    if (argc == 3) {
        curCfg["controller_worker"]["amp_boot_network_list"] = std::string(argv[1]);
        curCfg["controller_worker"]["amp_secgroup_list"] = std::string(argv[2]);
    }
    else {
        std::string nid = HexUtilPOpen(HEX_SDK " os_octavia_nid_get");
        std::string sgid = HexUtilPOpen(HEX_SDK " os_octavia_sgid_get");
        curCfg["controller_worker"]["amp_boot_network_list"] = nid;
        curCfg["controller_worker"]["amp_secgroup_list"] = sgid;
    }

    WriteConfig(CONF, SB_SEC_WFMT, '=', curCfg);
    CommitService(enabled);

    return EXIT_SUCCESS;
}

static void
ReinitUsage(void)
{
    fprintf(stderr, "Usage: %s reinit_octavia\n", HexLogProgramName());
}

static int
ReinitMain(int argc, char* argv[])
{
    if (argc > 1 /* [0]="reinit_octavia" */) {
        ReinitUsage();
        return EXIT_FAILURE;
    }

    if (G(IS_MASTER)) {
        std::string cidr = GetMgmtCidr(s_mgmtCidr.newValue(), 0);
        HexUtilSystemF(0, 0, HEX_SDK " os_octavia_init %s", cidr.c_str());
    }

    if (IsCompute(s_eCubeRole)) {
        std::string myip = G(MGMT_ADDR);
        std::string octet4 = hex_string_util::split(myip, '.')[3];
        // maps the 4th octet ranges from 1~9 to 11~19 for avoiding conflict with dhcp port
        if (octet4.length() == 1)
            octet4 = "1" + octet4;
        std::string cidr = GetMgmtCidr(s_mgmtCidr.newValue(), 0);
        std::string cidrIp = GetMgmtCidrIp(s_mgmtCidr.newValue(), 0, octet4);
        HexUtilSystemF(0, 0, HEX_SDK " os_octavia_node_init %s %s", cidrIp.c_str(), cidr.c_str());
    }

    if (IsControl(s_eCubeRole) || IsCompute(s_eCubeRole)) {
        ReconfigMain(1, NULL);
    }

    return EXIT_SUCCESS;
}

static int
ClusterReadyMain(int argc, char **argv)
{
    bool enabled = s_enabled;
    if (!enabled)
        return EXIT_SUCCESS;

    if (IsControl(s_eCubeRole)) {
        std::string cidr = GetMgmtCidr(s_mgmtCidr.newValue(), 0);
        HexUtilSystemF(0, 0, HEX_SDK " os_octavia_init %s", cidr.c_str());
    }

    return EXIT_SUCCESS;
}

static int
ClusterStartMain(int argc, char **argv)
{
    if (argc != 1)
        return EXIT_FAILURE;

    ReinitMain(1, NULL);

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(get_octavia_cidr_ip, GetMgmtCidrIpMain, GetMgmtCidrIpUsage);
CONFIG_COMMAND_WITH_SETTINGS(get_octavia_cidr, GetMgmtCidrMain, GetMgmtCidrUsage);
CONFIG_COMMAND_WITH_SETTINGS(restart_octavia, RestartMain, RestartUsage);
CONFIG_COMMAND_WITH_SETTINGS(reconfig_octavia, ReconfigMain, ReconfigUsage);
CONFIG_COMMAND_WITH_SETTINGS(reinit_octavia, ReinitMain, ReinitUsage);

CONFIG_MODULE(octavia, Init, Parse, 0, 0, Commit);

// startup sequence
CONFIG_REQUIRES(octavia, memcache);

// extra tunings
CONFIG_OBSERVES(octavia, rabbitmq, ParseRabbitMQ, NotifyMQ);
CONFIG_OBSERVES(octavia, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(octavia, keystone, ParseKeystone, NotifyKeystone);

CONFIG_MIGRATE(octavia, "/etc/octavia/certs");
CONFIG_MIGRATE(octavia, KEYFILE);
CONFIG_MIGRATE(octavia, KEYFILE_PUB);

CONFIG_TRIGGER_WITH_SETTINGS(octavia, "cluster_ready", ClusterReadyMain);
CONFIG_TRIGGER_WITH_SETTINGS(octavia, "cluster_start", ClusterStartMain);

