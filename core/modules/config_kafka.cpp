// CUBE

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include <hex/log.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/filesystem.h>
#include <hex/string_util.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <hex/logrotate.h>

#include <cube/systemd_util.h>
#include <cube/config_file.h>
#include <cube/cluster.h>

#include "include/role_cubesys.h"

#define DEF_EXT     ".def"
#define ZK_CONF     "/opt/kafka/config/zookeeper.properties"
#define KAFKA_CONF  "/opt/kafka/config/server.properties"

const static char ZK_NAME[] = "zookeeper";
const static char ZK_DATA[] = "/tmp/zookeeper";
const static char ZK_ID[] = "/tmp/zookeeper/myid";

const static char KAFKA_NAME[] = "kafka";
const static char KAFKA_META[] = "/var/lib/kafka/meta.properties";
const static char KAFKA_DIR[] = "/var/lib/kafka";

static Configs zkCfg;
static Configs kafkaCfg;

static ConfigString s_hostname;

static bool s_bCubeModified = false;
static bool s_bNetModified = false;

static CubeRole_e s_eCubeRole;

// rotate daily and enable copytruncate
static LogRotateConf zk_log_conf("zookeeper", "/var/log/zookeeper/*.log", DAILY, 128, 0, true);
static LogRotateConf kafka_log_conf("kafka", "/var/log/kafka/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_BOOL_REF(IS_MASTER);
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// private tunings
CONFIG_TUNING_BOOL(KAFKA_ENABLED, "kafka.enabled", TUNING_UNPUB, "Set to true to enable kafka.", true);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, KAFKA_ENABLED);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);

static bool
RecreateTopic(bool ha, bool run, const std::string sharedId, const char* topic)
{
    if (!run)
        return true;

    const char cmd[] = "/opt/kafka/bin/kafka-topics.sh";

    HexUtilSystemF(0, 0, "%s --delete --topic %s --bootstrap-server %s:9095 >/dev/null 2>&1",
                         cmd, topic, sharedId.c_str());

    if (std::string(topic) == "__consumer_offsets")
        return true;

    HexUtilSystemF(0, 0, "%s --create --topic %s --partitions 6 --bootstrap-server %s:9095 --replication-factor %d --if-not-exists >/dev/null 2>&1",
                         cmd, topic, sharedId.c_str(), ha ? 2 : 1);
    HexUtilSystemF(0, 0, "%s --alter --topic %s --partitions 6 --bootstrap-server %s:9095 >/dev/null 2>&1",
                         cmd, topic, sharedId.c_str());

    return true;
}

static bool
UpdateTopics(bool ha, bool run, const std::string sharedId)
{
    if (!run)
        return true;

    std::string topics[] = { "telegraf-metrics", "telegraf-hc-metrics", "telegraf-events-metrics", "metrics", "logs", "audit-logs",
                             "transformed-logs", "alarms", "notifications.info", "events" };

    for (const std::string &t : topics) {
        RecreateTopic(ha, true, sharedId, t.c_str());
    }
    RecreateTopic(ha, true, sharedId, "__consumer_offsets");

    return true;
}

static bool
UpdateCfg(bool ha, const std::string hostname, const std::string sharedId,
          const std::string ctrlIp, const std::string ctrlAddrs)
{
    if(IsControl(s_eCubeRole)) {
        int csize = GetClusterSize(ha, ctrlAddrs);

        HexSystemF(0, "echo \"0\" > %s", ZK_ID);

        zkCfg[GLOBAL_SEC]["autopurge.purgeInterval"] = "24";
        zkCfg[GLOBAL_SEC]["4lw.commands.whitelist"] = "stat,dump";

        HexSystemF(0, "echo \"version=0\" > %s", KAFKA_META);
        kafkaCfg[GLOBAL_SEC]["broker.id"] = "0";

        if (!ha) {
            zkCfg[GLOBAL_SEC]["standaloneEnabled"] = "true";
            HexSystemF(0, "echo \"broker.id=0\" >> %s", KAFKA_META);
        }
        else {
            zkCfg[GLOBAL_SEC]["standaloneEnabled"] = "false";
            zkCfg[GLOBAL_SEC]["initLimit"] = "5";
            zkCfg[GLOBAL_SEC]["syncLimit"] = "2";
            auto group = hex_string_util::split(ctrlAddrs, ',');
            for (size_t i = 0 ; i < group.size() ; i++) {
                if (ctrlIp == group[i]) {
                    if (csize >= 3) {
                        // zookeeper requires at least 3 nodes to form a quorum
                        HexSystemF(0, "echo \"%lu\" > %s", i, ZK_ID);
                        zkCfg[GLOBAL_SEC]["clientPortAddress"] = ctrlIp;
                    }
                    kafkaCfg[GLOBAL_SEC]["broker.id"] = std::to_string(i);
                    HexSystemF(0, "echo \"broker.id=%lu\" >> %s", i, KAFKA_META);
                }
                if (csize >= 3) {
                    std::string srvKey = "server." + std::to_string(i);
                    zkCfg[GLOBAL_SEC][srvKey] = group[i] + ":2888:3888";
                }
            }
        }

        kafkaCfg[GLOBAL_SEC]["listeners"] = "PLAINTEXT://" + ctrlIp + ":9095";
        kafkaCfg[GLOBAL_SEC]["zookeeper.connect"] = sharedId + ":2181";
        kafkaCfg[GLOBAL_SEC]["zookeeper.connection.timeout.ms"] = "60000";
        kafkaCfg[GLOBAL_SEC]["log.dirs"] = KAFKA_DIR;
        kafkaCfg[GLOBAL_SEC]["log.retention.bytes"] = "67108864";  // 64MB
        kafkaCfg[GLOBAL_SEC]["log.retention.ms"] = "300000";        // 5mins
        kafkaCfg[GLOBAL_SEC]["log.retention.hours"] = "0";
        kafkaCfg[GLOBAL_SEC]["log.retention.check.interval.ms"] = "1000";
        kafkaCfg[GLOBAL_SEC]["log.cleaner.delete.retention.ms"] = "1000";
    }

    return true;
}

static bool
Init()
{
    if (HexMakeDir(ZK_DATA, "zookeeper", "zookeeper", 0755) != 0)
        return false;

    // load masakari configurations
    if (!LoadConfig(ZK_CONF DEF_EXT, SB_SEC_RFMT, '=', zkCfg)) {
        HexLogError("failed to load %s config file %s", ZK_NAME, ZK_CONF);
        return false;
    }

    if (!LoadConfig(KAFKA_CONF DEF_EXT, SB_SEC_RFMT, '=', kafkaCfg)) {
        HexLogError("failed to load %s config file %s", KAFKA_NAME, KAFKA_CONF);
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

    return true;
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

static void
NotifyNet(bool modified)
{
    s_bNetModified = s_hostname.modified();
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
        return true;
    }

    return modified | s_bNetModified | s_bCubeModified | G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = IsControl(s_eCubeRole) && s_enabled;
    bool isMaster = G(IS_MASTER);
    std::string myip = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);

    UpdateCfg(s_ha, s_hostname.newValue(), sharedId, myip, s_ctrlAddrs.newValue());

    WriteConfig(ZK_CONF, SB_SEC_WFMT, '=', zkCfg);
    SystemdCommitService(enabled, ZK_NAME, true);
    WriteLogRotateConf(zk_log_conf);

    WriteConfig(KAFKA_CONF, SB_SEC_WFMT, '=', kafkaCfg);
    SystemdCommitService(enabled, KAFKA_NAME, true);
    WriteLogRotateConf(kafka_log_conf);

    // run update topics in non-master control nodes
    // master node zk may not have quorum in upgrade and cause a long run
    if (access(CUBE_MIGRATE, F_OK) == 0)
        UpdateTopics(s_ha, enabled & !isMaster, sharedId);

    return true;
}

static int
ClusterReadyMain(int argc, char **argv)
{
    bool isCtrl = IsControl(s_eCubeRole);
    std::string sharedId = G(SHARED_ID);
    UpdateTopics(s_ha, isCtrl, sharedId);

    return EXIT_SUCCESS;
}

static void
UpdateTopicUsage(void)
{
    fprintf(stderr, "Usage: %s update_kafka_topics\n", HexLogProgramName());
}

static int
UpdateTopicMain(int argc, char **argv)
{
    if (argc != 1) {
        UpdateTopicUsage();
        return EXIT_FAILURE;
    }

    bool isCtrl = IsControl(s_eCubeRole);
    std::string sharedId = G(SHARED_ID);
    UpdateTopics(s_ha, isCtrl, sharedId);

    return EXIT_SUCCESS;
}

static void
RecreateTopicUsage(void)
{
    fprintf(stderr, "Usage: %s recreate_kafka_topic [topic]\n", HexLogProgramName());
}

static int
RecreateTopicMain(int argc, char **argv)
{
    if (argc != 2) {
        RecreateTopicUsage();
        return EXIT_FAILURE;
    }

    bool isCtrl = IsControl(s_eCubeRole);
    std::string sharedId = G(SHARED_ID);
    RecreateTopic(s_ha, isCtrl, sharedId, argv[1]);

    return EXIT_SUCCESS;
}


CONFIG_COMMAND_WITH_SETTINGS(update_kafka_topics, UpdateTopicMain, UpdateTopicUsage);
CONFIG_COMMAND_WITH_SETTINGS(recreate_kafka_topic, RecreateTopicMain, RecreateTopicUsage);

CONFIG_MODULE(kafka, Init, Parse, 0, 0, Commit);
CONFIG_REQUIRES(kafka, cube_scan);

// extra tunings
CONFIG_OBSERVES(kafka, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(kafka, cubesys, ParseCube, NotifyCube);

CONFIG_SUPPORT_COMMAND(HEX_SDK " zookeeper_stats");
CONFIG_SUPPORT_COMMAND(HEX_SDK " kafka_stats");

CONFIG_TRIGGER_WITH_SETTINGS(kafka, "cluster_ready", ClusterReadyMain);

