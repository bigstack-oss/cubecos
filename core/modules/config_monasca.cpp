// CUBE

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/logrotate.h>
#include <hex/dryrun.h>

#include <cube/systemd_util.h>
#include <cube/config_file.h>
#include <cube/cluster.h>

#include "mysql_util.h"
#include "include/role_cubesys.h"

static const char USER[] = "monasca";
static const char GROUP[] = "monasca";

// monasca config files
#define DEF_EXT         ".def"
#define API_CONF        "/etc/monasca/api-config.conf"
#define PST_CONF        "/etc/monasca/persister.conf"
#define MONASCA_SQL     "/etc/monasca/monasca-mysql.sql"

#define IN_EXT ".in"
#define CEPH_YAML "/etc/monasca/agent/conf.d.in/ceph.yaml"
#define HAPROXY_YAML "/etc/monasca/agent/conf.d.in/haproxy.yaml"
#define LIBVIRT_YAML "/etc/monasca/agent/conf.d.in/libvirt.yaml"
#define MCACHE_YAML "/etc/monasca/agent/conf.d.in/mcache.yaml"
#define HTTP_CHECK_YAML "/etc/monasca/agent/conf.d.in/http_check.yaml"

#define CONF_D_DIR "/etc/monasca/agent/conf.d/"

static const char LOGDIR[] = "/var/log/monasca";

static const char NTF_CONF_IN[] = "/etc/monasca/notification.yaml.in";
static const char NTF_CONF[] = "/etc/monasca/notification.yaml";

static const char THRESH_CONF_IN[] = "/etc/monasca/thresh-config.yml.in";
static const char THRESH_CONF[] = "/etc/monasca/thresh-config.yml";

static const char AGENT_APACHE_CONF[] = "/root/.apache.cnf";
static const char AGENT_MYSQL_CONF[] = "/root/.my.cnf";

static const char AGENT_CONF_IN[] = "/etc/monasca/agent/agent.yaml.in";
static const char AGENT_CONF[] = "/etc/monasca/agent/agent.yaml";

static const char AGENT_SETUP_MARK[] = "/etc/appliance/state/monasca_agent_done";

// monasca-api
static const char API_NAME[] = "monasca-api";

// monasca-persister
static const char PST_NAME[] = "monasca-persister";

// monasca-agent
static const char AGT_NAME[] = "monasca-agent.target";

static const char CLT_NAME[] = "monasca-collector";
static const char FWD_NAME[] = "monasca-forwarder";
static const char STD_NAME[] = "monasca-statsd";

static const char OPENRC[] = "/etc/admin-openrc.sh";

static const char USERPASS[] = "FLCHzqeXyf6d63ZR";
static const char DBPASS[] = "pvDiNFbHpQwKnFdB";

static const char OSCMD[] = "/usr/bin/openstack";

static Configs apiCfg;
static Configs pstCfg;

static ConfigString s_hostname;

static bool s_bSetup = true;

static bool s_bNetModified = false;
static bool s_bCubeModified = false;
static bool s_bNovaModified = false;

static bool s_bDbPassChanged = false;
static bool s_bConfigChanged = false;
static bool s_bEndpointChanged = false;

static CubeRole_e s_eCubeRole;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("monasca", "/var/log/monasca/*.log", DAILY, 128, 0, true);
static LogRotateConf agent_log_conf("monasca-agent", "/var/log/monasca/agent/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(CTRL_IP);
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(MONASCA_ENABLED, "monasca.enabled", TUNING_UNPUB, "Set to true to enable monasca.", true);
CONFIG_TUNING_STR(MONASCA_USERPASS, "monasca.user.password", TUNING_UNPUB, "Set monasca user password.", USERPASS, ValidateNone);
CONFIG_TUNING_STR(MONASCA_DBPASS, "monasca.db.password", TUNING_UNPUB, "Set monasca database password.", DBPASS, ValidateNone);

// public tunings
CONFIG_TUNING_BOOL(MONASCA_DEBUG, "monasca.debug.enabled", TUNING_PUB, "Set to true to enable monasca verbose log.", false);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(RABBITMQ_OPENSTACK_PASSWD);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_REGION);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(NOVA_USERPASS);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, MONASCA_ENABLED);
PARSE_TUNING_BOOL(s_debug, MONASCA_DEBUG);
PARSE_TUNING_STR(s_monascaPass, MONASCA_USERPASS);
PARSE_TUNING_STR(s_dbPass, MONASCA_DBPASS);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 1);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);
PARSE_TUNING_X_STR(s_novaPass, NOVA_USERPASS, 2);

static bool
WriteAgentSetupDetectionConfigs()
{
    if (!IsControl(s_eCubeRole))
        return true;

    FILE *fout = fopen(AGENT_APACHE_CONF, "w");
    if (!fout) {
        HexLogError("Unable to write monasca agent apache plugin config: %s", AGENT_APACHE_CONF);
        return false;
    }

    fprintf(fout, "[client]\n");
    fprintf(fout, "url=http://localhost:8080/server-status?auto\n");
    fclose(fout);

    fout = fopen(AGENT_MYSQL_CONF, "w");
    if (!fout) {
        HexLogError("Unable to write monasca agent mysql plugin config: %s", AGENT_MYSQL_CONF);
        return false;
    }

    fprintf(fout, "[client]\n");
    fprintf(fout, "user=root\n");
    fprintf(fout, "socket=/var/lib/mysql/mysql.sock\n");
    fclose(fout);

    return true;
}

static bool
SyncAgentConf()
{
    // remove automatically generated but undesired modules
    HexSystemF(0, "rm -f %s/ceph.yaml", CONF_D_DIR);
    HexSystemF(0, "rm -f %s/disk.yaml", CONF_D_DIR);
    HexSystemF(0, "rm -f %s/congestion.yaml", CONF_D_DIR);

    if (IsControl(s_eCubeRole))
        HexSystemF(0, "mv %s/http_check.yaml %s/http_check.yaml.orig", CONF_D_DIR, CONF_D_DIR);

    if (IsControl(s_eCubeRole)) {
        HexSystemF(0, "cp -f %s %s %s " CONF_D_DIR,
                      HAPROXY_YAML, MCACHE_YAML, HTTP_CHECK_YAML);
    }

    if (IsCompute(s_eCubeRole)) {
        HexSystemF(0, "cp -f %s " CONF_D_DIR, LIBVIRT_YAML);
    }

    return true;
}

static bool
WriteAgentConfTemplates(const std::string& ctrlIp, const std::string& sharedId, const std::string& region,
                        const std::string& hostname, const std::string& novaPass)
{
    if (IsCompute(s_eCubeRole)) {
        if (HexSystemF(0, "sed -e \"s/@CUBE_SHARED_ID@/%s/\" -e \"s/@NOVA_PASS@/%s/\" "
                          "-e \"s/@CUBE_REGION@/%s/\" %s > %s",
                          sharedId.c_str(), novaPass.c_str(), region.c_str(),
                          LIBVIRT_YAML IN_EXT, LIBVIRT_YAML) != 0) {
            HexLogError("failed to update %s", LIBVIRT_YAML);
            return false;
        }
    }

    if (IsControl(s_eCubeRole)) {
        if (HexSystemF(0, "sed -e \"s/@CUBE_CTRL_IP@/%s/\" %s > %s",
                          ctrlIp.c_str(),
                          HAPROXY_YAML IN_EXT, HAPROXY_YAML) != 0) {
            HexLogError("failed to update %s", HAPROXY_YAML);
            return false;
        }

        if (HexSystemF(0, "sed -e \"s/@CUBE_CTRL_IP@/%s/\" %s > %s",
                          ctrlIp.c_str(),
                          MCACHE_YAML IN_EXT, MCACHE_YAML) != 0) {
            HexLogError("failed to update %s", MCACHE_YAML);
            return false;
        }

        if (HexSystemF(0, "sed -e \"s/@CUBE_SHARED_ID@/%s/\" %s > %s",
                          ctrlIp.c_str(),
                          HTTP_CHECK_YAML IN_EXT, HTTP_CHECK_YAML) != 0) {
            HexLogError("failed to update %s", HTTP_CHECK_YAML);
            return false;
        }
    }

    return true;
}

// should run after mysql services are running.
static bool
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if(!MysqlUtilIsDbExist("monasca")) {
        if (!MysqlUtilRunSQL("CREATE DATABASE monasca") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON monasca.* TO 'monasca'@'localhost' IDENTIFIED BY 'monasca_dbpass'") ||
            !MysqlUtilRunSQL("GRANT ALL PRIVILEGES ON monasca.* TO 'monasca'@'%' IDENTIFIED BY 'monasca_dbpass'")) {
            return false;
        }

        s_bSetup = false;
    }

    return true;
}

// should run after keystone & mysql services are running.
static bool
SetupMonasca(std::string domain, std::string userPass)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Setting up monasca");

    // Populate the monasca service database
    HexUtilSystemF(0, 0, "su -s /bin/sh -c \"/usr/local/bin/monasca_db upgrade\" %s", USER);

    // prepare env settings
    std::string env = ". " + std::string(OPENRC) + " &&";

    // Create the monasca service credentials
    HexUtilSystemF(0, 0, "%s %s user create --domain %s --password %s monasca",
                         env.c_str(), OSCMD, domain.c_str(), userPass.c_str());
    HexUtilSystemF(0, 0, "%s %s role add --project service --user monasca admin", env.c_str(), OSCMD);

    // Create the service entity
    HexUtilSystemF(0, 0, "%s %s service create --name monasca-api "
                         "--description \"monasca monitoring service\" monitoring",
                         env.c_str(), OSCMD);

    return true;
}

static bool
UpdateEndpoint(std::string endpoint, std::string external, std::string region)
{
    if (!IsControl(s_eCubeRole))
        return true;

    HexLogInfo("Updating monasca endpoints");

    std::string pub = "http://" + external + ":8070/v2.0";
    std::string adm = "http://" + endpoint + ":8070/v2.0";
    std::string intr = "http://" + endpoint + ":8070/v2.0";

    HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_update %s %s %s %s %s",
                         "monitoring", region.c_str(), pub.c_str(), adm.c_str(), intr.c_str());

    return true;
}

static bool
WriteTemplateConfigs(bool ha, const std::string& hostname, const std::string& region,
                     const std::string& sharedId, const std::string& userpass, const std::string& dbpass)
{
    if (IsUndef(s_eCubeRole))
        return true;

    if (HexSystemF(0, "sed -e \"s/@CUBE_SHARED_ID@/%s/\" -e \"s/@MONASCA_PASS@/%s/\" "
                       "-e \"s/@MONASCA_REGION@/%s/\" -e \"s/@CUBE_HOST@/%s/\" %s > %s",
                      sharedId.c_str(), userpass.c_str(), region.c_str(), hostname.c_str(),
                      AGENT_CONF_IN, AGENT_CONF) != 0) {
        HexLogError("failed to update %s", AGENT_CONF);
        return false;
    }

    return true;
}

static bool
UpdateDbConn(std::string sharedId, std::string password)
{
    if(IsControl(s_eCubeRole)) {
        std::string dbconn = "mysql+pymysql://monasca:";
        dbconn += password;
        dbconn += "@";
        dbconn += sharedId;
        dbconn += "/monasca?charset=utf8mb4";

        apiCfg["database"]["connection"] = dbconn;
    }

    return true;
}

static bool
UpdateSharedId(std::string sharedId)
{
    if(IsControl(s_eCubeRole)) {
        apiCfg["influxdb"]["ip_address"] = sharedId;
        apiCfg["keystone_authtoken"]["memcached_servers"] = sharedId + ":11211";
        apiCfg["keystone_authtoken"]["www_authenticate_uri"] = "http://" + sharedId + ":5000";
        apiCfg["keystone_authtoken"]["auth_url"] = "http://" + sharedId + ":5000";

        pstCfg["influxdb"]["ip_address"] = sharedId;
        pstCfg["zookeeper"]["uri"] = sharedId + ":2181";
    }

    return true;
}

static bool
UpdateKafkaConn(const bool ha, std::string sharedId, std::string ctrlAddrs)
{
    if (IsControl(s_eCubeRole)) {
        // FIXME: api/persistor cannot use shared ip to consume kafka messages?
        std::string server = KafkaServers(ha, sharedId, ctrlAddrs);
        apiCfg["kafka"]["uri"] = server;

        pstCfg["kafka_alarm_history"]["uri"] = server;
        pstCfg["kafka_metrics"]["uri"] = server;
    }

    return true;
}

static bool
UpdateDebug(bool enabled)
{
    std::string value = enabled ? "true" : "false";
    apiCfg["DEFAULT"]["debug"] = value;
    pstCfg["DEFAULT"]["debug"] = value;

    return true;
}

static bool
UpdateCfg(std::string region, std::string domain, std::string userPass, std::string hostname)
{
    if(IsControl(s_eCubeRole)) {
        apiCfg["keystone_authtoken"]["auth_type"] = "password";
        apiCfg["keystone_authtoken"]["project_domain_name"] = domain;
        apiCfg["keystone_authtoken"]["user_domain_name"] = domain;
        apiCfg["keystone_authtoken"]["project_name"] = "service";
        apiCfg["keystone_authtoken"]["username"] = "monasca";
        apiCfg["keystone_authtoken"]["password"] = userPass;

        pstCfg["DEFAULT"]["log_config_append"] = "/etc/monasca/persister-logging.conf";

        pstCfg["repositories"]["metrics_driver"] = "monasca_persister.repositories.influxdb.metrics_repository:MetricInfluxdbRepository";
        pstCfg["repositories"]["alarm_state_history_driver"] = "monasca_persister.repositories.influxdb.alarm_state_history_repository:AlarmStateHistInfluxdbRepository";

        pstCfg["zookeeper"]["partition_interval_recheck_seconds"] = "15";

        pstCfg["kafka_alarm_history"]["topic"] = "alarms";
        pstCfg["kafka_alarm_history"]["group_id"] = "monasca-persister-alarm";
        pstCfg["kafka_alarm_history"]["consumer_id"] = hostname;
        pstCfg["kafka_alarm_history"]["zookeeper_path"] = "/persister_partitions/monasca-persister-alarm";
        pstCfg["kafka_alarm_history"]["num_processors"] = "2";

        pstCfg["kafka_metrics"]["topic"] = "metrics";
        pstCfg["kafka_metrics"]["group_id"] = "monasca-persister-metrics";
        pstCfg["kafka_metrics"]["consumer_id"] = hostname;
        pstCfg["kafka_metrics"]["zookeeper_path"] = "/persister_partitions/monasca-persister-metrics";
        pstCfg["kafka_metrics"]["num_processors"] = "2";
        // write to kapacitor instead of influxdb directly for potential alerts
        pstCfg["influxdb"]["database_name"] = "monasca";
        pstCfg["influxdb"]["port"] = "9092";
    }

    return true;
}

static bool
MonascaAgentSetup(const bool enabled)
{
    HexSystemF(0, "mv %s %s.good", AGENT_CONF, AGENT_CONF);
    HexSystemF(0, "rm -rf /etc/monasca/agent/conf.d/*");
    WriteAgentSetupDetectionConfigs();
    std::string env = ". " + std::string(OPENRC) + " &&";
    HexUtilSystemF(0, 0, "%s /usr/local/bin/monasca-setup -u $OS_USERNAME -p $OS_PASSWORD "
                         "--project_name $OS_PROJECT_NAME --project_domain_name $OS_PROJECT_DOMAIN_NAME "
                         "--user_domain_name $OS_USER_DOMAIN_NAME --keystone_url $OS_AUTH_URL", env.c_str());
    HexSystemF(0, "mv %s.good %s", AGENT_CONF, AGENT_CONF);
    // remove script generated service files
    HexSystemF(0, "rm -f /etc/systemd/system/monasca-collector.service /etc/systemd/system/monasca-forwarder.service");
    HexSystemF(0, "systemctl daemon-reload");
    SyncAgentConf();
    SystemdCommitService(enabled, CLT_NAME);
    SystemdCommitService(enabled, FWD_NAME);
    SystemdCommitService(enabled, STD_NAME);
    HexSystemF(0, "systemctl disable %s >/dev/null 2>&1", AGT_NAME);

    return true;
}

static bool
MonascaSetupService(const bool enabled)
{
    if (!IsUndef(s_eCubeRole)) {
        struct stat ms;
        if (stat(AGENT_SETUP_MARK, &ms) != 0) {
            MonascaAgentSetup(enabled);
            HexSystemF(0, "touch %s", AGENT_SETUP_MARK);
        }
        else {
            SyncAgentConf();
            SystemdCommitService(enabled, CLT_NAME);
            SystemdCommitService(enabled, FWD_NAME);
            SystemdCommitService(enabled, STD_NAME);
        }
    }

    return true;
}

static bool
MonascaService(const bool enabled)
{
    if(IsControl(s_eCubeRole)) {
        SystemdCommitService(enabled, PST_NAME);
    }

    return true;
}

static bool
Init()
{
    // load monasca configurations
    if (!LoadConfig(API_CONF DEF_EXT, SB_SEC_RFMT, '=', apiCfg)) {
        HexLogError("failed to load monasca api config file %s", API_CONF);
        return false;
    }

    if (!LoadConfig(PST_CONF DEF_EXT, SB_SEC_RFMT, '=', pstCfg)) {
        HexLogError("failed to load monasca persister config file %s", PST_CONF);
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
ParseNet(const char *name, const char *value, bool isNew)
{
    if (strcmp(name, NET_HOSTNAME) == 0) {
        s_hostname.parse(value, isNew);
    }

    return true;
}

static bool
ParseCube(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 1);
    return true;
}

static bool
ParseNova(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 2);
    return true;
}

static void
NotifyNet(bool modified)
{
    s_bNetModified = s_hostname.modified();
}

static void
NotifyCube(bool modified)
{
    s_bCubeModified = IsModifiedTune(1);
    s_eCubeRole = GetCubeRole(s_cubeRole);
}

static void
NotifyNova(bool modified)
{
    s_bNovaModified = IsModifiedTune(2);
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        s_bConfigChanged = true;
        return true;
    }

    s_bDbPassChanged = s_dbPass.modified() | s_bCubeModified;

    s_bConfigChanged = modified | s_bCubeModified |
                 s_bNetModified | s_bNovaModified |
                 G_MOD(CTRL_IP) | G_MOD(SHARED_ID);

    s_bEndpointChanged = s_bNetModified | s_bCubeModified |
                       G_MOD(SHARED_ID) | G_MOD(EXTERNAL);

    return s_bDbPassChanged | s_bConfigChanged | s_bEndpointChanged;
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

    std::string monascaPass = GetSaltKey(s_saltkey, s_monascaPass.newValue(), s_seed.newValue());
    std::string dbPass = GetSaltKey(s_saltkey, s_dbPass.newValue(), s_seed.newValue());
    std::string novaPass = GetSaltKey(s_saltkey, s_novaPass.newValue(), s_seed.newValue());

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
        UpdateCfg(s_cubeRegion.newValue(), s_cubeDomain.newValue(),
                  monascaPass, s_hostname.newValue());
        UpdateSharedId(sharedId);
        UpdateDbConn(sharedId, dbPass);
        UpdateKafkaConn(s_ha, sharedId, s_ctrlAddrs.newValue());
        UpdateDebug(s_debug.newValue());

        WriteTemplateConfigs(s_ha, s_hostname.newValue(), s_cubeRegion.newValue(),
                             sharedId, monascaPass, dbPass);
        WriteAgentConfTemplates(ctrlIp, sharedId, s_cubeRegion.newValue(),
                                s_hostname.newValue(), novaPass);
        WriteConfig(API_CONF, SB_SEC_WFMT, '=', apiCfg);
        WriteConfig(PST_CONF, SB_SEC_WFMT, '=', pstCfg);
    }

    // configuring openstack sevice
    if (!s_bSetup)
        SetupMonasca(s_cubeDomain.newValue(), monascaPass);

    // check for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_monasca_db");

    // configuring openstack end point
    if (s_bEndpointChanged)
        UpdateEndpoint(sharedId, external, s_cubeRegion.newValue());

    // service kick off
    MonascaService(s_enabled);

    WriteLogRotateConf(log_conf);
    WriteLogRotateConf(agent_log_conf);

    return true;
}

static bool
CommitLast(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    MonascaSetupService(s_enabled);

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_monasca\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    MonascaService(s_enabled);

    return EXIT_SUCCESS;
}

static void
SetupUsage(void)
{
    fprintf(stderr, "Usage: %s setup_monasca_agent\n", HexLogProgramName());
}

static int
SetupMain(int argc, char* argv[])
{
    if (argc != 1) {
        SetupUsage();
        return EXIT_FAILURE;
    }

    MonascaAgentSetup(true);

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_monasca, RestartMain, RestartUsage);
CONFIG_COMMAND_WITH_SETTINGS(setup_monasca_agent, SetupMain, SetupUsage);

CONFIG_MODULE(monasca, Init, Parse, 0, 0, Commit);
CONFIG_MODULE(monasca_setup, 0, 0, 0, 0, CommitLast);

// startup sequence
CONFIG_REQUIRES(monasca, memcache);
//CONFIG_REQUIRES(monasca, kafka);
//CONFIG_REQUIRES(monasca, influxdb);

// monasca-setup auto detects all supported running processes
CONFIG_LAST(monasca_setup);
CONFIG_REQUIRES(monasca_setup, pacemaker_last);

// extra tunings
CONFIG_OBSERVES(monasca, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(monasca, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(monasca, nova, ParseNova, NotifyNova);

