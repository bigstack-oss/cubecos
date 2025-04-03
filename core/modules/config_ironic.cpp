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

#include <cube/systemd_util.h>
#include <cube/config_file.h>
#include <cube/cluster.h>

#include "mysql_util.h"
#include "include/role_cubesys.h"

static const char USER[] = "ironic";
static const char GROUP[] = "ironic";

static const char INSP_USER[] = "ironic-inspector";
static const char INSP_GROUP[] = "ironic-inspector";

// ironic config files
#define DEF_EXT     ".def"
#define CONF        "/etc/ironic/ironic.conf"
#define INSP_CONF   "/etc/ironic-inspector/inspector.conf"
#define AGT_CONF    "/etc/neutron/plugins/ml2/ironic_neutron_agent.ini"

// ironic common
static const char RUNDIR[] = "/run/ironic";
static const char INSP_RUNDIR[] = "/var/run/ironic-inspector";

// ironic services
static const char API_NAME[] = "openstack-ironic-api";
static const char CDT_NAME[] = "openstack-ironic-conductor";
static const char INSP_NAME[] = "openstack-ironic-inspector";
static const char DNS_NAME[] = "openstack-ironic-inspector-dnsmasq";
static const char IRONIC_NAME[] = "openstack-nova-ironic-compute";
static const char AGT_NAME[] = "ironic-neutron-agent";
static const char FILE_NAME[] = "openstack-ironic-file-server";

// tftp/pxe server
static const char TFTP_ROOT[] = "/tftpboot";
static const char DHCP_TFTP_CFG[] = "/etc/ironic-inspector/dnsmasq.conf";
static const char PXE_CFG[] = "/tftpboot/pxelinux.cfg/default";
static const char IRONIC_CFG_SYNC[] = "/etc/cron.d/ironic_config_sync";

static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char USERPASS[] = "Rf5jKHUrqRIRhw9Z";
static const char INSPPASS[] = "zwV64adt04oqAuAO";
static const char DBPASS[] = "bMkbMPKXwhBckKhY";
static const char INSPDBPASS[] = "2XZyAEwkYLPWasWK";

static const char OSCMD[] = "/usr/bin/openstack";

static Configs cfg;
static Configs inspCfg;
static Configs agtCfg;

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
CONFIG_TUNING_BOOL(IRONIC_ENABLED, "ironic.enabled", TUNING_UNPUB, "Set to true to enable ironic.", false);
CONFIG_TUNING_STR(IRONIC_USERPASS, "ironic.user.password", TUNING_UNPUB, "Set ironic user password.", USERPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(IRONIC_INSPPASS, "ironic.inspector.user.password", TUNING_UNPUB, "Set ironic user password.", INSPPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(IRONIC_DBPASS, "ironic.db.password", TUNING_UNPUB, "Set ironic database password.", DBPASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(IRONIC_INSPDBPASS, "ironic.inspector.db.password", TUNING_UNPUB, "Set ironic inspector database password.", INSPDBPASS, ValidateRegex, DFT_REGEX_STR);

// public tunings
CONFIG_TUNING_BOOL(IRONIC_DEBUG, "ironic.debug.enabled", TUNING_PUB, "Set to true to enable ironic verbose log.", false);
CONFIG_TUNING_BOOL(IRONIC_DEPLOY_SERVER, "ironic.deploy.server", TUNING_PUB, "Set to true to enable ironic deploy server (dhcp/tftp/pxe/http).", false);

// using external tunings
CONFIG_TUNING_SPEC_STR(RABBITMQ_OPENSTACK_PASSWD);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_REGION);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, IRONIC_ENABLED);
PARSE_TUNING_BOOL(s_deployEnabled, IRONIC_DEPLOY_SERVER);
PARSE_TUNING_BOOL(s_debug, IRONIC_DEBUG);
PARSE_TUNING_STR(s_ironicPass, IRONIC_USERPASS);
PARSE_TUNING_STR(s_inspPass, IRONIC_INSPPASS);
PARSE_TUNING_STR(s_dbPass, IRONIC_DBPASS);
PARSE_TUNING_STR(s_inspDbPass, IRONIC_INSPDBPASS);
PARSE_TUNING_X_STR(s_mqPass, RABBITMQ_OPENSTACK_PASSWD, 1);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 2);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 2);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 2);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 2);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 2);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 2);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 2);

static bool
CronConfigSync(bool enabled)
{
    if(IsControl(s_eCubeRole) && enabled) {
        FILE *fout = fopen(IRONIC_CFG_SYNC, "w");
        if (!fout) {
            HexLogError("Unable to write %s", IRONIC_CFG_SYNC);
            return false;
        }

        fprintf(fout, "*/3 * * * * root " HEX_SDK " os_ironic_config_sync\n");
        fclose(fout);

        if(HexSetFileMode(IRONIC_CFG_SYNC, "root", "root", 0644) != 0) {
            HexLogError("Unable to set file %s mode/permission", IRONIC_CFG_SYNC);
            return false;
        }
    }
    else {
        unlink(IRONIC_CFG_SYNC);
    }

    return true;
}

static bool
WriteDhcpTftpConfig()
{
    if (!IsControl(s_eCubeRole))
        return true;

    FILE *fout = fopen(DHCP_TFTP_CFG, "w");
    if (!fout) {
        HexLogError("Unable to write %s", DHCP_TFTP_CFG);
        return false;
    }

    // disable dns
    fprintf(fout, "port=0\n");

    fprintf(fout, "bind-interfaces\n");

    // enable tftp
    fprintf(fout, "enable-tftp\n");
    fprintf(fout, "tftp-root=/tftpboot\n");

    // enable pxe
    fprintf(fout, "dhcp-boot=pxelinux.0\n");
    fclose(fout);

    return true;
}

static bool
WritePxeConfig(const std::string& sharedId)
{
    if (!IsControl(s_eCubeRole))
        return true;

    FILE *fout = fopen(PXE_CFG, "w");
    if (!fout) {
        HexLogError("Unable to write %s", PXE_CFG);
        return false;
    }

    fprintf(fout, "default introspect\n");
    fprintf(fout, "\n");
    fprintf(fout, "label introspect\n");
    fprintf(fout, "kernel deploy.kernel\n");
    fprintf(fout, "append initrd=deploy.initrd ipa-inspection-callback-url=http://%s:5050/v1/continue "
                  "ipa-inspection-collectors=default,logs systemd.journald.forward_to_console=yes\n", sharedId.c_str());
    fprintf(fout, "\n");
    fprintf(fout, "ipappend 3\n");

    fclose(fout);

    return true;
}

// should run after mysql services are running.
static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if(!MysqlUtilIsDbExist("ironic")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE ironic") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON ironic.* TO 'ironic'@'localhost' IDENTIFIED BY 'ironic_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON ironic.* TO 'ironic'@'%' IDENTIFIED BY 'ironic_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    if(!MysqlUtilIsDbExist("ironic_inspector")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE ironic_inspector") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON ironic_inspector.* TO 'ironic-inspector'@'localhost' IDENTIFIED BY 'ironic_insp_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON ironic_inspector.* TO 'ironic-inspector'@'%' IDENTIFIED BY 'ironic_insp_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

// should run after keystone & mysql services are running.
static bool
SetupIronic(std::string domain, std::string ironicPass, std::string inspPass)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up ironic");

    // Populate the ironic services database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"ironic-dbsync --config-file " CONF " create_schema\" %s", USER);
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"ironic-inspector-dbsync --config-file " INSP_CONF " upgrade\" %s", INSP_USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the ironic roles
    HexUtilSystemF(0, 0, "%s %s role create baremetal_admin", env.c_str(), OSCMD);
    HexUtilSystemF(0, 0, "%s %s role create baremetal_observer", env.c_str(), OSCMD);

    // Create the ironic service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s ironic",
                         env.c_str(), OSCMD, domain.c_str(), ironicPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user ironic admin", env.c_str(), OSCMD);

    // Create the ironic service entity
    HexUtilSystemF(0, 0, "%s %s service create --name ironic "
                         "--description \"Ironic baremetal provisioning service\" baremetal",
                         env.c_str(), OSCMD);

    // Create the ironic-inspector service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s ironic-inspector",
                         env.c_str(), OSCMD, domain.c_str(), inspPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user ironic-inspector admin", env.c_str(), OSCMD);

    // Create the ironic-inspector service entity
    HexUtilSystemF(0, 0, "%s %s service create --name ironic-inspector "
                         "--description \"Ironic Inspector baremetal introspection service\" baremetal-introspection",
                         env.c_str(), OSCMD);
    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating ironic endpoints");

    std::string pub = "http://" + external + ":6385";
    std::string adm = "http://" + endpoint + ":6385";
    std::string intr = "http://" + endpoint + ":6385";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "baremetal", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    pub = "http://" + external + ":5050";
    adm = "http://" + endpoint + ":5050";
    intr = "http://" + endpoint + ":5050";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "baremetal-introspection", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static bool
UpdateDbConn(std::string sharedId, std::string password, std::string inspPass)
{
    if(IsControl(s_eCubeRole)) {
        std::string dbconn = "mysql+pymysql://ironic:";
        dbconn += password;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/ironic";

        cfg["database"]["connection"] = dbconn;

        dbconn = "mysql+pymysql://ironic-inspector:";
        dbconn += inspPass;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/ironic_inspector";

        inspCfg["database"]["connection"] = dbconn;
    }

    return true;
}

static bool
UpdateMyIp(std::string myip)
{
    if(IsControl(s_eCubeRole)) {
        cfg["api"]["host_ip"] = myip;
        inspCfg["DEFAULT"]["listen_address"] = myip;
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
        cfg["deploy"]["http_url"] = "http://" + sharedId + ":8484";
        cfg["oslo_messaging_notifications"]["transport_url"] = "kafka://" + sharedId + ":9095";

        inspCfg["keystone_authtoken"]["memcached_servers"] = sharedId + ":11211";
        inspCfg["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        inspCfg["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";
        inspCfg["coordination"]["backend_url"] = "memcached://" + sharedId + ":11211";
        inspCfg["oslo_messaging_notifications"]["transport_url"] = "kafka://" + sharedId + ":9095";

        agtCfg["ironic"]["memcached_servers"] = sharedId + ":11211";
        agtCfg["ironic"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        agtCfg["ironic"]["auth_url"] = "http://" + sharedId + ":5000";
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
        inspCfg["DEFAULT"]["transport_url"] = dbconn;
        inspCfg["DEFAULT"]["rpc_response_timeout"] = "1200";

        if (ha) {
            cfg["oslo_messaging_rabbit"]["rabbit_retry_interval"] = "1";
            cfg["oslo_messaging_rabbit"]["rabbit_retry_backoff"] = "2";
            cfg["oslo_messaging_rabbit"]["amqp_durable_queues"] = "true";
            cfg["oslo_messaging_rabbit"]["rabbit_ha_queues"] = "true";

            inspCfg["oslo_messaging_rabbit"]["rabbit_retry_interval"] = "1";
            inspCfg["oslo_messaging_rabbit"]["rabbit_retry_backoff"] = "2";
            inspCfg["oslo_messaging_rabbit"]["amqp_durable_queues"] = "true";
            inspCfg["oslo_messaging_rabbit"]["rabbit_ha_queues"] = "true";
        }
    }

    return true;
}

static bool
UpdateDebug(bool enabled)
{
    std::string value = enabled ? "true" : "false";
    cfg["DEFAULT"]["debug"] = value;
    inspCfg["DEFAULT"]["debug"] = value;

    return true;
}

static bool
UpdateCfg(std::string domain, std::string ironicPass, std::string inspPass)
{
    if(IsControl(s_eCubeRole)) {
        cfg["DEFAULT"]["auth_strategy"] = "keystone";
        cfg["DEFAULT"]["log_dir"] = "/var/log/ironic";

        cfg["DEFAULT"]["enabled_hardware_types"] = "ipmi";
        cfg["DEFAULT"]["enabled_boot_interfaces"] = "pxe";
        cfg["DEFAULT"]["enabled_deploy_interfaces"] = "direct";
        cfg["DEFAULT"]["enabled_inspect_interfaces"] = "inspector";
        cfg["DEFAULT"]["enabled_management_interfaces"] = "ipmitool";
        cfg["DEFAULT"]["enabled_network_interfaces"] = "flat,noop";

        cfg["keystone_authtoken"].clear();
        cfg["keystone_authtoken"]["auth_type"] = "password";
        cfg["keystone_authtoken"]["project_domain_name"] = domain.c_str();
        cfg["keystone_authtoken"]["user_domain_name"] = domain.c_str();
        cfg["keystone_authtoken"]["project_name"] = "service";
        cfg["keystone_authtoken"]["username"] = "ironic";
        cfg["keystone_authtoken"]["password"] = ironicPass.c_str();

        cfg["glance"]["auth_section"] = "keystone_authtoken";
        cfg["nova"]["auth_section"] = "keystone_authtoken";
        cfg["neutron"]["auth_section"] = "keystone_authtoken";
        cfg["swift"]["auth_section"] = "keystone_authtoken";
        cfg["cinder"]["auth_section"] = "keystone_authtoken";
        cfg["inspector"]["auth_section"] = "keystone_authtoken";
        cfg["service_catalog"]["auth_section"] = "keystone_authtoken";

        cfg["inspector"]["enabled"] = "true";
        cfg["dhcp"]["dhcp_provider"] = "neutron";

        cfg["conductor"]["automated_clean"] = "false";
        cfg["neutron"]["cleaning_network"] = "";

        cfg["agent"]["image_download_source"] = "http";
        cfg["agent"]["deploy_logs_local_path"] = "/var/log/ironic";
        cfg["agent"]["deploy_logs_storage_backend"] = "local";
        cfg["agent"]["deploy_logs_collect"] = "always";

        cfg["agent"]["deploy_logs_collect"] = "always";
        cfg["deploy"]["http_root"] = "/tftpboot/images";

        cfg["oslo_messaging_notifications"]["driver"] = "messagingv2";

        inspCfg["DEFAULT"]["log_dir"] = "/var/log/ironic-inspector";
        inspCfg["DEFAULT"]["standalone"] = "true";

        inspCfg["keystone_authtoken"].clear();
        inspCfg["keystone_authtoken"]["auth_type"] = "password";
        inspCfg["keystone_authtoken"]["project_domain_name"] = domain.c_str();
        inspCfg["keystone_authtoken"]["user_domain_name"] = domain.c_str();
        inspCfg["keystone_authtoken"]["project_name"] = "service";
        inspCfg["keystone_authtoken"]["username"] = "ironic-inspector";
        inspCfg["keystone_authtoken"]["password"] = inspPass.c_str();

        inspCfg["ironic"]["ramdisk_logs_dir"] = "/var/log/ironic-inspector/ramdisk";
        inspCfg["ironic"]["store_data"] = "swift";

        inspCfg["ironic"]["auth_section"] = "keystone_authtoken";
        inspCfg["swift"]["auth_section"] = "keystone_authtoken";

        inspCfg["oslo_messaging_notifications"]["driver"] = "messagingv2";

        agtCfg["ironic"].clear();
        agtCfg["ironic"]["auth_type"] = "password";
        agtCfg["ironic"]["project_domain_name"] = domain.c_str();
        agtCfg["ironic"]["user_domain_name"] = domain.c_str();
        agtCfg["ironic"]["project_name"] = "service";
        agtCfg["ironic"]["username"] = "ironic";
        agtCfg["ironic"]["password"] = ironicPass.c_str();

        if (IsControl(s_eCubeRole)) {
            std::string workers = std::to_string(GetControlWorkers(IsConverged(s_eCubeRole), IsEdge(s_eCubeRole)));
            cfg["api"]["api_workers"] = workers;
        }
    }

    return true;
}

static bool
IronicService(const bool enabled, const bool deploy)
{
    if (IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled, API_NAME);
        SystemdCommitService(enabled, CDT_NAME);
        SystemdCommitService(enabled, AGT_NAME);
        SystemdCommitService(enabled, INSP_NAME);
        SystemdCommitService(deploy && enabled, DNS_NAME);
        SystemdCommitService(deploy && enabled, FILE_NAME);
    }

    if (IsCompute(s_eCubeRole)) {
        SystemdCommitService(enabled, IRONIC_NAME, true);
    }

    return true;
}

static bool
Init()
{
    if (HexMakeDir(RUNDIR, USER, GROUP, 0755) != 0)
        return false;

    if (HexMakeDir(INSP_RUNDIR, INSP_USER, INSP_GROUP, 0755) != 0)
        return false;

    if (HexMakeDir(TFTP_ROOT, USER, GROUP, 0755) != 0)
        return false;

    // load ironic configurations
    if (!LoadConfig(CONF DEF_EXT, SB_SEC_RFMT, '=', cfg)) {
        HexLogError("failed to load ironic config file %s", CONF);
        return false;
    }

    if (!LoadConfig(INSP_CONF DEF_EXT, SB_SEC_RFMT, '=', inspCfg)) {
        HexLogError("failed to load ironic-inspector config file %s", CONF);
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

    s_bDbPassChanged = s_dbPass.modified() | s_inspDbPass.modified() | s_bCubeModified;

    s_bConfigChanged = modified | s_bMqModified |
                s_bCubeModified | G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID);

    s_bEndpointChanged = s_bCubeModified | G_MOD(SHARED_ID) | G_MOD(EXTERNAL);

    return s_bDbPassChanged | s_bConfigChanged | s_bEndpointChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || IsEdge(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    std::string myip = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    std::string ironicPass = GetSaltKey(s_saltkey, s_ironicPass.newValue(), s_seed.newValue());
    std::string inspPass = GetSaltKey(s_saltkey, s_inspPass.newValue(), s_seed.newValue());
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());
    std::string inspDbPass = GetSaltKey(s_saltkey, s_inspDbPass.newValue(), s_seed.newValue());
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass.newValue(), s_seed.newValue());

    SetupCheck();
    if (!s_bSetup) {
        s_bDbPassChanged = true;
        s_bEndpointChanged = true;
    }

    // update mysql db user password
    if (s_bDbPassChanged && IsControl(s_eCubeRole)) {
        MysqlUtilUpdateDbPass(USER, dbPass.c_str());
        MysqlUtilUpdateDbPass(INSP_USER, inspDbPass.c_str());
    }

    // update config file
    if (s_bConfigChanged) {
        UpdateCfg(s_cubeDomain.newValue(), ironicPass, inspPass);
        UpdateSharedId(sharedId);
        UpdateMyIp(myip);
        UpdateDbConn(sharedId, dbPass, inspDbPass);
        UpdateMqConn(s_ha, sharedId, mqPass, s_ctrlAddrs.newValue());
        UpdateDebug(s_debug.newValue());

        WritePxeConfig(sharedId);
        WriteDhcpTftpConfig();
        WriteConfig(CONF, SB_SEC_WFMT, '=', cfg);
        WriteConfig(INSP_CONF, SB_SEC_WFMT, '=', inspCfg);
        WriteConfig(AGT_CONF, SB_SEC_WFMT, '=', agtCfg);
    }

    // configuring openstack sevice
    if (!s_bSetup)
        SetupIronic(s_cubeDomain.newValue(), ironicPass, inspPass);

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_ironic_db");

    // configuring openstack end point
    if (s_bEndpointChanged)
        UpdateEndpoint(sharedId, external, s_cubeRegion.newValue());

    CronConfigSync(s_deployEnabled);

    // service kickoff
    IronicService(s_enabled, s_deployEnabled);

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_ironic\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    IronicService(s_enabled, s_deployEnabled);

    return EXIT_SUCCESS;
}

static void
InitDhcpCfgUsage(void)
{
    fprintf(stderr, "Usage: %s init_ironic_dhcp_config\n", HexLogProgramName());
}

static int
InitDhcpCfgMain(int argc, char* argv[])
{
    if (argc != 1) {
        InitDhcpCfgUsage();
        return EXIT_FAILURE;
    }

    WriteDhcpTftpConfig();

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_ironic, RestartMain, RestartUsage);
CONFIG_COMMAND_WITH_SETTINGS(init_ironic_dhcp_config, InitDhcpCfgMain, InitDhcpCfgUsage);

CONFIG_MODULE(ironic, Init, Parse, 0, 0, Commit);
// startup sequence
CONFIG_REQUIRES(ironic, memcache);
CONFIG_REQUIRES(ironic, nova);

// extra tunings
CONFIG_OBSERVES(ironic, rabbitmq, ParseRabbitMQ, NotifyMQ);
CONFIG_OBSERVES(ironic, cubesys, ParseCube, NotifyCube);
