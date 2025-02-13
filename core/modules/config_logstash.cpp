// CUBE

#include <hex/log.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <hex/logrotate.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <cube/systemd_util.h>
#include <cube/cluster.h>

#include "include/role_cubesys.h"

#define IN_EXT ".in"
#define LG_TSM "/etc/logstash/conf.d/log-transformer.conf"
#define AG_TSM "/etc/logstash/conf.d/auditlog-transformer.conf"
#define LG_EMP "/etc/logstash/conf.d/hex-event-mapper.conf"
#define OS_EMP "/etc/logstash/conf.d/ops-event-mapper.conf"
#define CE_EMP "/etc/logstash/conf.d/ceph-event-mapper.conf"
#define KN_EMP "/etc/logstash/conf.d/kernel-event-mapper.conf"
#define LG_TPR "/etc/logstash/conf.d/telegraf-persister.conf"
#define LG_TPR_HC "/etc/logstash/conf.d/telegraf-hc-persister.conf"
#define LG_TPR_EV "/etc/logstash/conf.d/telegraf-events-persister.conf"
#define LOG_TPL "/etc/logstash/logs-ec-template.json"
#define DEF_TPL "/etc/logstash/default-ec-template.json"

const static char LG_NAME[] = "logstash";
const static char FB_NAME[] = "filebeat";
const static char AB_NAME[] = "auditbeat";
const static char LG_CONF[] = "/etc/logstash/logstash.yml";
const static char FB_CONF[] = "/etc/filebeat/filebeat.yml";
const static char AB_CONF[] = "/etc/auditbeat/auditbeat.yml";

static ConfigString s_hostname;

static CubeRole_e s_eCubeRole;

static bool s_bNetModified = false;
static bool s_bCubeModified = false;

// rotate daily and enable copytruncate
static LogRotateConf lg_log_conf("logstash", "/var/log/logstash/*.log", DAILY, 128, 0, true);
static LogRotateConf fb_log_conf("filebeat", "/var/log/filebeat/filebeat", DAILY, 128, 0, true);
static LogRotateConf ab_log_conf("auditbeat", "/var/log/auditbeat/auditbeat", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);

// parse tunings
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);

static bool
WriteConfigs(const std::string &kafkaHosts)
{
    FILE *fout = fopen(LG_CONF, "w");
    if (!fout)
    {
        HexLogError("Unable to write %s config: %s", LG_NAME, LG_CONF);
        return false;
    }

    fprintf(fout, "path.data: /var/lib/logstash\n");
    fprintf(fout, "path.logs: /var/log/logstash\n");
    fprintf(fout, "queue.type: persisted\n");
    fprintf(fout, "queue.max_bytes: 128mb\n");
    fclose(fout);

    fout = fopen(FB_CONF, "w");
    if (!fout)
    {
        HexLogError("Unable to write %s config: %s", FB_NAME, FB_CONF);
        return false;
    }

    fprintf(fout, "filebeat.inputs:\n");
    fprintf(fout, "- type: log\n");
    fprintf(fout, "  paths:\n");
    fprintf(fout, "    - /var/log/messages\n");
    fprintf(fout, "    - /var/log/keystone/*.log\n");
    fprintf(fout, "    - /var/log/nova/*.log\n");
    fprintf(fout, "    - /var/log/glance/*.log\n");
    fprintf(fout, "    - /var/log/cinder/*.log\n");
    fprintf(fout, "    - /var/log/neutron/*.log\n");
    fprintf(fout, "    - /var/log/manila/*.log\n");
    fprintf(fout, "    - /var/log/heat/*.log\n");
    fprintf(fout, "    - /var/log/octavia/*.log\n");
    fprintf(fout, "    - /var/log/ironic/*.log\n");
    fprintf(fout, "    - /var/log/ironic-inspector/*.log\n");
    fprintf(fout, "    - /var/log/masakari/*.log\n");
    fprintf(fout, "    - /var/log/httpd/*.log\n");
    fprintf(fout, "    - /var/log/ceph/ceph.log\n");
#if 0 /* uncomment until logstash supports its log processing */
    fprintf(fout, "    - /var/log/pacemaker.log\n");
    fprintf(fout, "    - /var/log/httpd/*.log\n");
    fprintf(fout, "    - /var/log/rabbitmq/*.log\n");
    fprintf(fout, "    - /var/log/zookeeper/*.log\n");
    fprintf(fout, "    - /var/log/opensearch/*.log\n");
    fprintf(fout, "    - /var/log/ec235/*.log\n");
    fprintf(fout, "    - /var/log/grafana/*.log\n");
    fprintf(fout, "    - /var/log/influxdb/*.log\n");
    fprintf(fout, "    - /var/log/kapacitor/*.log\n");
    fprintf(fout, "    - /var/log/telegraf/*.log\n");
    // the below 2 logs should take care carefully otherwise they cause log loopping
    fprintf(fout, "    - /var/log/monasca/*.log\n");
    fprintf(fout, "    - /var/log/logstash/*.log\n");
#endif
    fprintf(fout, "\n");

    fprintf(fout, "output.kafka:\n");
    fprintf(fout, "  hosts: [%s]\n", kafkaHosts.c_str());
    fprintf(fout, "  topic: 'logs'\n");
    fprintf(fout, "  partition.round_robin:\n");
    fprintf(fout, "    reachable_only: false\n");
    fprintf(fout, "  required_acks: 1\n");
    fprintf(fout, "  max_message_bytes: 1000000\n");
    fprintf(fout, "\n");

    fclose(fout);

    fout = fopen(AB_CONF, "w");
    if (!fout)
    {
        HexLogError("Unable to write %s config: %s", AB_NAME, AB_CONF);
        return false;
    }

    fprintf(fout, "auditbeat.modules:\n");
    fprintf(fout, "- module: file_integrity\n");
    fprintf(fout, "  paths:\n");
    fprintf(fout, "    - /bin\n");
    fprintf(fout, "    - /usr/bin\n");
    fprintf(fout, "    - /sbin\n");
    fprintf(fout, "    - /usr/sbin\n");
    fprintf(fout, "    - /etc\n");
    fprintf(fout, "  exclude_files:\n");
    fprintf(fout, "    - '(?i)\\.sw[nop]$'\n");
    fprintf(fout, "    - '~$'\n");
    fprintf(fout, "    - '/\\.git($|/)'\n");
    fprintf(fout, "  scan_at_start: true\n");
    fprintf(fout, "  scan_rate_per_sec: 50 MiB\n");
    fprintf(fout, "  max_file_size: 100 MiB\n");
    fprintf(fout, "  hash_types: [sha1]\n");
    fprintf(fout, "  recursive: false\n");
    fprintf(fout, "\n");

    fprintf(fout, "output.kafka:\n");
    fprintf(fout, "  hosts: [%s]\n", kafkaHosts.c_str());
    fprintf(fout, "  topic: 'audit-logs'\n");
    fprintf(fout, "  partition.round_robin:\n");
    fprintf(fout, "    reachable_only: false\n");
    fprintf(fout, "  required_acks: 1\n");
    fprintf(fout, "  max_message_bytes: 1000000\n");
    fprintf(fout, "\n");

    fclose(fout);

    return true;
}

static bool
WriteTemplateConfigs(bool ha, const std::string &hostname,
                     const std::string &sharedId, const std::string &kafkaHosts)
{
    if (!IsControl(s_eCubeRole))
        return true;

    if (HexSystemF(0, "sed -e \"s/@KAFKA_HOSTS@/%s/\" -e \"s/@CUBE_SHARED_ID@/%s/\" -e \"s/@CUBE_HOST@/%s/\" %s > %s",
                   kafkaHosts.c_str(), sharedId.c_str(), hostname.c_str(),
                   LG_TSM IN_EXT, LG_TSM) != 0)
    {
        HexLogError("failed to update %s", LG_TSM);
        return false;
    }

    if (HexSystemF(0, "sed -e \"s/@KAFKA_HOSTS@/%s/\" -e \"s/@CUBE_SHARED_ID@/%s/\" -e \"s/@CUBE_HOST@/%s/\" %s > %s",
                   kafkaHosts.c_str(), sharedId.c_str(), hostname.c_str(),
                   AG_TSM IN_EXT, AG_TSM) != 0)
    {
        HexLogError("failed to update %s", AG_TSM);
        return false;
    }

    if (HexSystemF(0, "sed -e \"s/@KAFKA_HOSTS@/%s/\" -e \"s/@CUBE_SHARED_ID@/%s/\" -e \"s/@CUBE_HOST@/%s/\" %s > %s",
                   kafkaHosts.c_str(), sharedId.c_str(), hostname.c_str(),
                   LG_EMP IN_EXT, LG_EMP) != 0)
    {
        HexLogError("failed to update %s", LG_EMP);
        return false;
    }

    if (HexSystemF(0, "sed -e \"s/@KAFKA_HOSTS@/%s/\" -e \"s/@CUBE_SHARED_ID@/%s/\" -e \"s/@CUBE_HOST@/%s/\" %s > %s",
                   kafkaHosts.c_str(), sharedId.c_str(), hostname.c_str(),
                   OS_EMP IN_EXT, OS_EMP) != 0)
    {
        HexLogError("failed to update %s", OS_EMP);
        return false;
    }

    if (HexSystemF(0, "sed -e \"s/@KAFKA_HOSTS@/%s/\" -e \"s/@CUBE_SHARED_ID@/%s/\" -e \"s/@CUBE_HOST@/%s/\" %s > %s",
                   kafkaHosts.c_str(), sharedId.c_str(), hostname.c_str(),
                   CE_EMP IN_EXT, CE_EMP) != 0)
    {
        HexLogError("failed to update %s", CE_EMP);
        return false;
    }

    if (HexSystemF(0, "sed -e \"s/@KAFKA_HOSTS@/%s/\" -e \"s/@CUBE_SHARED_ID@/%s/\" -e \"s/@CUBE_HOST@/%s/\" %s > %s",
                   kafkaHosts.c_str(), sharedId.c_str(), hostname.c_str(),
                   KN_EMP IN_EXT, KN_EMP) != 0)
    {
        HexLogError("failed to update %s", KN_EMP);
        return false;
    }

    if (HexSystemF(0, "sed -e \"s/@KAFKA_HOSTS@/%s/\" -e \"s/@CUBE_SHARED_ID@/%s/\" -e \"s/@CUBE_HOST@/%s/\" %s > %s",
                   kafkaHosts.c_str(), sharedId.c_str(), hostname.c_str(),
                   LG_TPR IN_EXT, LG_TPR) != 0)
    {
        HexLogError("failed to update %s", LG_TPR);
        return false;
    }

    if (HexSystemF(0, "sed -e \"s/@KAFKA_HOSTS@/%s/\" -e \"s/@CUBE_SHARED_ID@/%s/\" -e \"s/@CUBE_HOST@/%s/\" %s > %s",
                       kafkaHosts.c_str(), sharedId.c_str(), hostname.c_str(),
                       LG_TPR_HC IN_EXT, LG_TPR_HC) != 0)
    {
        HexLogError("failed to update %s", LG_TPR_HC);
        return false;
    }

    if (HexSystemF(0, "sed -e \"s/@KAFKA_HOSTS@/%s/\" -e \"s/@CUBE_SHARED_ID@/%s/\" -e \"s/@CUBE_HOST@/%s/\" %s > %s",
                       kafkaHosts.c_str(), sharedId.c_str(), hostname.c_str(),
                       LG_TPR_EV IN_EXT, LG_TPR_EV) != 0)
    {
        HexLogError("failed to update %s", LG_TPR_EV);
        return false;
    }

    if (HexSystemF(0, "sed -e \"s/@EC_SHARDS@/%d/\" -e \"s/@EC_REPLICAS@/%d/\" %s > %s",
                      ha ? 2 : 1, ha ? 1 : 0, LOG_TPL IN_EXT, LOG_TPL) != 0)
    {
        HexLogError("failed to update %s", LOG_TPL);
        return false;
    }

    if (HexSystemF(0, "sed -e \"s/@EC_SHARDS@/%d/\" -e \"s/@EC_REPLICAS@/%d/\" %s > %s",
                      1, ha ? 1 : 0, DEF_TPL IN_EXT, DEF_TPL) != 0)
    {
        HexLogError("failed to update %s", DEF_TPL);
        return false;
    }

    return true;
}

static bool
CommitService(bool enabled)
{
    if (IsUndef(s_eCubeRole))
        return true;

    if (IsControl(s_eCubeRole) && !IsModerator(s_eCubeRole)) {
        SystemdCommitService(enabled, LG_NAME);
    }

    SystemdCommitService(enabled, FB_NAME);
    SystemdCommitService(enabled, AB_NAME);

    return true;
}

static bool
ParseNet(const char *name, const char *value, bool isNew)
{
    if (strcmp(name, NET_HOSTNAME) == 0)
    {
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

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        return true;
    }

    return modified | s_bNetModified | s_bCubeModified | G_MOD(SHARED_ID);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    std::string sharedId = G(SHARED_ID);
    std::string kafkaHosts = KafkaServers(false, sharedId, "");
    std::string qkafkaHosts = KafkaServers(false, sharedId, "", true);

    WriteTemplateConfigs(s_ha, s_hostname, sharedId, kafkaHosts);
    WriteConfigs(qkafkaHosts);

    CommitService(true);

    if (IsControl(s_eCubeRole) && !IsModerator(s_eCubeRole))
        WriteLogRotateConf(lg_log_conf);
    WriteLogRotateConf(fb_log_conf);
    WriteLogRotateConf(ab_log_conf);

    return true;
}

CONFIG_MODULE(logstash, 0, 0, 0, 0, Commit);
CONFIG_REQUIRES(logstash, kafka);

// extra tunings
CONFIG_OBSERVES(logstash, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(logstash, cubesys, ParseCube, NotifyCube);

