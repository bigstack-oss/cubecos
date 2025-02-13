// CUBE

#include <unistd.h>
#include <sstream>

#include <hex/log.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/string_util.h>
#include <hex/filesystem.h>
#include <hex/logrotate.h>

#include <cube/systemd_util.h>
#include <cube/cluster.h>

#include "include/role_cubesys.h"

static const char NAME[] = "kapacitor";

#define DEF_EXT ".def"
#define CONF_PATH "/etc/kapacitor/"
#define CONF        CONF_PATH "kapacitor.conf"
#define TASK_DIR    CONF_PATH "tasks/"
#define TPL_DIR     CONF_PATH "templates/"
#define HDR_DIR     CONF_PATH "handlers/"
#define CFGHDR_DIR  CONF_PATH "config_handlers/"
#define EXTRA_DIR   CONF_PATH "alert_extra/"
#define TELEGRAF_DB "telegraf"
#define CEPH_DB "ceph"
#define MONASCA_DB "monasca"
#define EVENTS_DB "events"
#define TSDB_RP "def"
#define HC_TSDB_RP "hc"
#define ALERT_CHECKER     "/etc/systemd/system/alert-checker.service"
#define ALERT_TIMER       "/etc/systemd/system/alert-checker.timer"

static std::vector<std::string> s_telegrafTasks = {
    "cpu",
    "disk",
    "diskio",
    "kernel",
    "mem",
    "net",
    "processes",
    "swap",
    "system",
};

static std::vector<std::string> s_cephTasks = {
    "ceph_daemon_stats",
    "ceph_pool_stats",
};


static bool s_bNetModified = false;
static bool s_bCubeModified = false;

static ConfigString s_hostname;
static CubeRole_e s_eCubeRole;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("kapacitor", "/var/log/kapacitor/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// public tunigns
CONFIG_TUNING_BOOL(KAPACITOR_ALERT_CHK_ENABLED, "kapacitor.alert.check.enabled", TUNING_PUB, "Set true to enable kapacitor alert check.", false);
CONFIG_TUNING_STR(KAPACITOR_ALERT_CHK_EID, "kapacitor.alert.check.eventid", TUNING_PUB, "Set kapacitor alert check eventid.", "SYS00002W", ValidateNone);
CONFIG_TUNING_STR(KAPACITOR_ALERT_CHK_INTERVAL, "kapacitor.alert.check.interval", TUNING_PUB, "Set kapacitor alert check interval (default to 60m).", "60m", ValidateNone);
CONFIG_TUNING_STR(KAPACITOR_ALERT_FLOW_BASE, "kapacitor.alert.flow.base", TUNING_PUB, "Set kapacitor alert base for abnormal flow.", "7d", ValidateNone);
CONFIG_TUNING_STR(KAPACITOR_ALERT_FLOW_UNIT, "kapacitor.alert.flow.unit", TUNING_PUB, "Set kapacitor alert unit for abnormal flow.", "5m", ValidateNone);
CONFIG_TUNING_INT(KAPACITOR_ALERT_FLOW_THRESHOLD, "kapacitor.alert.flow.threshold", TUNING_PUB, "Set kapacitor alert threshold for abnormal flow.", 30, 0, 65535);
CONFIG_TUNING_STR(KAPACITOR_ALERT_EXTRA_PREFIX, "kapacitor.alert.extra.prefix", TUNING_PUB, "Set kapacitor alert message prefix.", "Cube", ValidateNone);

// private tunigns
CONFIG_TUNING_UINT(KAPACITOR_ALERT_DEF_CRIT, "kapacitor.alert.default.crit", TUNING_UNPUB, "Set kapacitor alert default critical threshold.", 95 , 0, 100);
CONFIG_TUNING_UINT(KAPACITOR_ALERT_DEF_WARN, "kapacitor.alert.default.warn", TUNING_UNPUB, "Set kapacitor alert default warning threshold.", 85 , 0, 100);
CONFIG_TUNING_UINT(KAPACITOR_ALERT_DEF_INFO, "kapacitor.alert.default.info", TUNING_UNPUB, "Set kapacitor alert default info threshold.", 75 , 0, 100);
CONFIG_TUNING_STR(KAPACITOR_ALERT_RESP_ID, "kapacitor.alert.resp.%d.name", TUNING_UNPUB, "Set kapacitor alert response id.", "", ValidateNone);
CONFIG_TUNING_STR(KAPACITOR_ALERT_RESP_TOPIC, "kapacitor.alert.resp.%d.topic", TUNING_UNPUB, "Set kapacitor alert response topic.", "", ValidateNone);
CONFIG_TUNING_STR(KAPACITOR_ALERT_RESP_MATCH, "kapacitor.alert.resp.%d.match", TUNING_UNPUB, "Set kapacitor alert response match.", "", ValidateNone);
CONFIG_TUNING_STR(KAPACITOR_ALERT_RESP_TYPE, "kapacitor.alert.resp.%d.type", TUNING_UNPUB, "Set kapacitor alert response type 'slack', 'email', 'exec'.", "", ValidateNone);
CONFIG_TUNING_STR(KAPACITOR_ALERT_SLACK_URL, "kapacitor.alert.resp.%d.slack.url", TUNING_UNPUB, "Set kapacitor slack alert url.", "", ValidateNone);
CONFIG_TUNING_STR(KAPACITOR_ALERT_SLACK_CHANNEL, "kapacitor.alert.resp.%d.slack.channel", TUNING_UNPUB, "Set kapacitor slack alert channel.", "", ValidateNone);
CONFIG_TUNING_STR(KAPACITOR_ALERT_EMAIL_HOST, "kapacitor.alert.resp.%d.email.host", TUNING_UNPUB, "Set kapacitor email alert host.", "", ValidateNone);
CONFIG_TUNING_UINT(KAPACITOR_ALERT_EMAIL_PORT, "kapacitor.alert.resp.%d.email.port", TUNING_UNPUB, "Set kapacitor email alert port.", 0, 0, 65535);
CONFIG_TUNING_STR(KAPACITOR_ALERT_EMAIL_USER, "kapacitor.alert.resp.%d.email.username", TUNING_UNPUB, "Set kapacitor email alert username.", "", ValidateNone);
CONFIG_TUNING_STR(KAPACITOR_ALERT_EMAIL_PASS, "kapacitor.alert.resp.%d.email.password", TUNING_UNPUB, "Set kapacitor email alert password.", "", ValidateNone);
CONFIG_TUNING_STR(KAPACITOR_ALERT_EMAIL_FROM, "kapacitor.alert.resp.%d.email.from", TUNING_UNPUB, "Set kapacitor email alert from.", "", ValidateNone);
CONFIG_TUNING_STR(KAPACITOR_ALERT_EMAIL_TO, "kapacitor.alert.resp.%d.email.to", TUNING_UNPUB, "Set kapacitor email alert to.", "", ValidateNone);
CONFIG_TUNING_STR(KAPACITOR_ALERT_EXEC_TYPE, "kapacitor.alert.resp.%d.exec.type", TUNING_UNPUB, "Set kapacitor executable alert type 'shell', 'bin'.", "", ValidateNone);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_HOSTS);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);

// parse tunings
PARSE_TUNING_BOOL(s_alertChkEnabled, KAPACITOR_ALERT_CHK_ENABLED);
PARSE_TUNING_STR(s_alertChkEventId, KAPACITOR_ALERT_CHK_EID);
PARSE_TUNING_STR(s_alertChkInterval, KAPACITOR_ALERT_CHK_INTERVAL);
PARSE_TUNING_STR(s_alertExtraPrefix, KAPACITOR_ALERT_EXTRA_PREFIX);
PARSE_TUNING_UINT(s_alertDefCrit, KAPACITOR_ALERT_DEF_CRIT);
PARSE_TUNING_UINT(s_alertDefWarn, KAPACITOR_ALERT_DEF_WARN);
PARSE_TUNING_UINT(s_alertDefInfo, KAPACITOR_ALERT_DEF_INFO);
PARSE_TUNING_STR_ARRAY(s_respIdArr, KAPACITOR_ALERT_RESP_ID);
PARSE_TUNING_STR_ARRAY(s_respTopicArr, KAPACITOR_ALERT_RESP_TOPIC);
PARSE_TUNING_STR_ARRAY(s_respMatchArr, KAPACITOR_ALERT_RESP_MATCH);
PARSE_TUNING_STR_ARRAY(s_respTypeArr, KAPACITOR_ALERT_RESP_TYPE);
PARSE_TUNING_STR_ARRAY(s_slackUrlArr, KAPACITOR_ALERT_SLACK_URL);
PARSE_TUNING_STR_ARRAY(s_slackChannelArr, KAPACITOR_ALERT_SLACK_CHANNEL);
PARSE_TUNING_STR_ARRAY(s_emailHostArr, KAPACITOR_ALERT_EMAIL_HOST);
PARSE_TUNING_UINT_ARRAY(s_emailPortArr, KAPACITOR_ALERT_EMAIL_PORT);
PARSE_TUNING_STR_ARRAY(s_emailUserArr, KAPACITOR_ALERT_EMAIL_USER);
PARSE_TUNING_STR_ARRAY(s_emailPassArr, KAPACITOR_ALERT_EMAIL_PASS);
PARSE_TUNING_STR_ARRAY(s_emailFromArr, KAPACITOR_ALERT_EMAIL_FROM);
PARSE_TUNING_STR_ARRAY(s_emailToArr, KAPACITOR_ALERT_EMAIL_TO);
PARSE_TUNING_STR_ARRAY(s_execTypeArr, KAPACITOR_ALERT_EXEC_TYPE);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_ctrlHosts, CUBESYS_CONTROL_HOSTS, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);

static std::string
CheckerStr(const std::string& eventid, const std::string& hostname)
{
    std::string data;

    data = "[Unit]\n";
    data += "Description=alert checker\n";
    data += "\n";
    data += "[Service]\n";
    data += "Type=oneshot\n";
    data += "ExecStart=-/usr/sbin/hex_log_event -e " + eventid + " node=" + hostname + "\n";

    return data;
}

static std::string
TimerStr(const std::string& interval)
{
    std::string data;

    data += "[Unit]\n";
    data += "Description=alert check timer\n";
    data += "\n";
    data += "[Timer]\n";
    data += "Unit=alert-checker.service\n";
    data += "OnBootSec=" + interval + "\n";
    data += "OnUnitActiveSec=" + interval + "\n";
    data += "\n";
    data += "[Install]\n";
    data += "WantedBy=timers.target\n";

    return data;
}

static bool
CronAlertCheck(bool enabled, const std::string& eventid,
               const std::string& hostname, const std::string& interval)
{
    if(enabled) {
        std::string checkerStr = CheckerStr(eventid, hostname);
        FILE *fout = fopen(ALERT_CHECKER, "w");
        if (!fout) {
            HexLogError("Could not write alert checker file: %s", ALERT_CHECKER);
            return false;
        }

        fprintf(fout, "%s", checkerStr.c_str());
        fclose(fout);

        HexSetFileMode(ALERT_CHECKER, "root", "root", 0644);

        std::string timerStr = TimerStr(interval);
        fout = fopen(ALERT_TIMER, "w");
        if (!fout) {
            HexLogError("Could not write alert timer file: %s", ALERT_TIMER);
            return false;
        }

        fprintf(fout, "%s", timerStr.c_str());
        fclose(fout);

        HexSetFileMode(ALERT_TIMER, "root", "root", 0644);

        HexSystemF(0, "/usr/bin/systemctl enable alert-checker.timer 2>/dev/null");
        HexSystemF(0, "/usr/bin/systemctl start alert-checker.timer 2>/dev/null");
    }
    else {
        HexSystemF(0, "/usr/bin/systemctl disable alert-checker.timer 2>/dev/null");
        HexSystemF(0, "/usr/bin/systemctl stop alert-checker.timer 2>/dev/null");
        unlink(ALERT_CHECKER);
        unlink(ALERT_TIMER);
    }

    return true;
}

std::string
AddQuote(const std::string& list)
{
    auto group = hex_string_util::split(list, ',');
    std::string output = "";
    for (size_t i = 0 ; i < group.size() ; i++) {
        output += "\"" + group[i] + "\"";
        if (i + 1 < group.size())
            output += ", ";
    }

    return output;
}

static const std::string
EscapeDoubleQuote(const std::string &str)
{
    // 1. Escape each single quoat(") to '\"'
    std::stringstream out;
    for (std::string::const_iterator it = str.begin(); it != str.end(); it++) {
        if (*it == '"')
            out << "\\\"";
        else
            out << *it;
    }
    return out.str();
}

static bool
WriteEmailEventHandler(const std::string& name, const std::string& topic, const std::string& match, const std::string& to)
{
    std::string fname = CFGHDR_DIR "email_" + name + ".yaml";

    FILE *fout = fopen(fname.c_str(), "w");
    if (!fout) {
        HexLogError("Unable to write email event handler : %s", fname.c_str());
        return false;
    }

    fprintf(fout, "id: %s\n", name.c_str());
    fprintf(fout, "topic: %s\n", topic.c_str());
    fprintf(fout, "kind: smtp\n");
    if (match.length()) {
        // comply with yaml format
        fprintf(fout, "match: \"%s\"\n", EscapeDoubleQuote(match).c_str());
    }
    fprintf(fout, "options:\n");
    fprintf(fout, "  to:\n");

    auto group = hex_string_util::split(to, ',');
    for (size_t i = 0 ; i < group.size() ; i++) {
        fprintf(fout, "    - %s\n", group[i].c_str());
    }

    fclose(fout);

    return true;
}

static bool
WriteSlackEventHandler(const std::string& name, const std::string& topic, const std::string& match)
{
    std::string fname = CFGHDR_DIR "slack_" + name + ".yaml";

    FILE *fout = fopen(fname.c_str(), "w");
    if (!fout) {
        HexLogError("Unable to write slack event handler : %s", fname.c_str());
        return false;
    }

    fprintf(fout, "id: %s\n", name.c_str());
    fprintf(fout, "topic: %s\n", topic.c_str());
    fprintf(fout, "kind: slack\n");
    if (match.length()) {
        // comply with yaml format
        fprintf(fout, "match: \"%s\"\n", EscapeDoubleQuote(match).c_str());
    }
    fprintf(fout, "options:\n");
    fprintf(fout, "  workspace: '%s'\n", name.c_str());

    fclose(fout);

    return true;
}

static bool
WriteExecEventHandler(const std::string& name, const std::string& topic, const std::string& match, const std::string& type)
{
    std::string fname = CFGHDR_DIR "exec_" + name + ".yaml";

    FILE *fout = fopen(fname.c_str(), "w");
    if (!fout) {
        HexLogError("Unable to write executable event handler : %s", fname.c_str());
        return false;
    }

    fprintf(fout, "id: exec-%s-%s\n", name.c_str(), type.c_str());
    fprintf(fout, "topic: %s\n", topic.c_str());
    fprintf(fout, "kind: exec\n");
    if (match.length()) {
        // comply with yaml format
        fprintf(fout, "match: \"%s\"\n", EscapeDoubleQuote(match).c_str());
    }
    fprintf(fout, "options:\n");
    fprintf(fout, "  prog: '/usr/sbin/hex_config'\n");
    fprintf(fout, "  args: ['sdk_run', 'alert_resp_runner', '%s', '%s']\n", name.c_str(), type.c_str());

    fclose(fout);

    return true;
}


static bool
WriteConfig(const std::vector<std::string>& peerNames, const std::vector<std::string>& peerAddrs)
{
    if (HexSystemF(0, "cp -f %s %s", CONF DEF_EXT, CONF) != 0) {
        HexLogError("Failed to copy default kapacitor config %s", CONF DEF_EXT);
        return false;
    }

    std::ofstream ofsConf(CONF, std::ofstream::out | std::ofstream::app);
    if (!ofsConf.is_open()) {
        HexLogError("Unable to open config: %s", CONF);
        return false;
    }

    // Has HA peers
    if (peerNames.size() && peerAddrs.size() && peerNames.size() == peerAddrs.size()) {
        auto iName = peerNames.cbegin();
        auto iAddr = peerAddrs.cbegin();
        for(; iName != peerNames.end() && iAddr != peerAddrs.end(); iName++, iAddr++) {
            ofsConf << std::endl;
            ofsConf << "[[influxdb]]" << std::endl;
            ofsConf << "  enabled = true" << std::endl;
            ofsConf << "  disable-subscriptions = true" << std::endl;
            ofsConf << "  name = \"" << *iName << "\"" << std::endl;
            ofsConf << "  urls = [\"http://" << *iAddr << ":8086\"]" << std::endl;
            ofsConf << "  timeout = \"10s\"" << std::endl;
        }

    }

    HexSystemF(0, "rm -f " CFGHDR_DIR "*");
    bool emailSet = false;
    for (unsigned i = 0 ; i < s_respIdArr.size() ; i++) {
        if (s_respIdArr.newValue(i).length() == 0)
            continue;

        std::string name = s_respIdArr.newValue(i);
        std::string match = s_respMatchArr.newValue(i);
        std::string type = s_respTypeArr.newValue(i);
        std::string topic = s_respTopicArr.newValue(i);

        if (type == "slack") {
            std::string url = s_slackUrlArr.newValue(i);
            std::string channel = s_slackChannelArr.newValue(i);
            std::string def = (topic == "events") ? "true" : "false";

            ofsConf << std::endl;
            ofsConf << "[[slack]]" << std::endl;
            ofsConf << "  enabled = true" << std::endl;
            ofsConf << "  default = " << def << std::endl;
            ofsConf << "  workspace = \"" << name << "\"" << std::endl;
            ofsConf << "  url = \"" << url << "\"" << std::endl;
            ofsConf << "  username = \"CubeAlertBot\"" << std::endl;
            if (channel.length() && channel != "null") {
                ofsConf << "  channel = \"#" << channel << "\"" << std::endl;
            }
            ofsConf << "  global = false" << std::endl;
            ofsConf << "  state-changes-only = false" << std::endl;

            WriteSlackEventHandler(name, topic, match);
        }
        else if (type == "email") {
            std::string to = s_emailToArr.newValue(i);

            if (!emailSet) {
                std::string host = s_emailHostArr.newValue(i);
                int64_t port = s_emailPortArr.newValue(i);
                std::string username = s_emailUserArr.newValue(i);
                std::string password = s_emailPassArr.newValue(i);
                std::string from = s_emailFromArr.newValue(i);

                ofsConf << std::endl;
                ofsConf << "[smtp]" << std::endl;
                ofsConf << "  enabled = true" << std::endl;
                ofsConf << "  host = \"" << host << "\"" << std::endl;
                ofsConf << "  port = " << std::to_string(port) << std::endl;
                ofsConf << "  username = \"" << username << "\"" << std::endl;
                ofsConf << "  password = \"" << password << "\"" << std::endl;
                ofsConf << "  from = \"" << from << "\"" << std::endl;
                ofsConf << "  to = [ " << AddQuote(to) << " ]" << std::endl;
                ofsConf << "  no-verify = true" << std::endl;
                ofsConf << "  idle-timeout = \"180s\"" << std::endl;
                ofsConf << "  global = false" << std::endl;
                ofsConf << "  state-changes-only = false" << std::endl;
                emailSet = true;
            }

            WriteEmailEventHandler(name, topic, match, to);
        }
        else if (type == "exec") {
            std::string t = s_execTypeArr.newValue(i);
            WriteExecEventHandler(name, topic, match, t);
        }
    }

    ofsConf.close();

    return true;
}

static bool
WriteRelayTask(const std::string& db, const std::string& rp, const std::vector<std::string>& peerNames)
{
    if (HexMakeDir(TASK_DIR, "root", "root", 0755) != 0) {
        HexLogWarning("failed to create kapacitor task directory %s", TASK_DIR);
        return false;
    }

    std::string taskName = "relay_" + db + "_" + rp;
    std::string taskFile = TASK_DIR + taskName + ".tick";
    FILE *fout = fopen(taskFile.c_str(), "w");
    if (!fout) {
        HexLogError("Unable to write %s task: %s", NAME, taskFile.c_str());
        return false;
    }

    fprintf(fout, "dbrp \"%s\".\"%s\"\n", db.c_str(), rp.c_str());
    fprintf(fout, "\n");
    fprintf(fout, "var data = stream\n");
    fprintf(fout, "    |from()\n");
    fprintf(fout, "        .database('%s')\n", db.c_str());

    std::vector<std::string> outDBs = {"localhost"};
    outDBs.insert(outDBs.end(), peerNames.begin(), peerNames.end());

    auto iName = outDBs.cbegin();
    for(; iName != outDBs.end(); iName++) {
        fprintf(fout, "data\n");
        fprintf(fout, "    |influxDBOut()\n");
        fprintf(fout, "        .cluster('%s')\n", (*iName).c_str());
        fprintf(fout, "        .database('%s')\n", db.c_str());
        fprintf(fout, "        .retentionPolicy('%s')\n", rp.c_str());
    }
    fclose(fout);

    return true;
}

static bool
WriteAlertExtra(const std::string& msgPrefix)
{
    if (HexMakeDir(EXTRA_DIR, "root", "root", 0755) != 0) {
        HexLogWarning("failed to create kapacitor alert extra directory %s", EXTRA_DIR);
        return false;
    }

    HexUtilSystemF(0, 0, HEX_SDK " alert_extra_update %s", msgPrefix.c_str());

    return true;
}

static bool
DefineTasks()
{
    HexSystemF(0, "find " TASK_DIR " -name '*.tick' -exec sh -c 'kapacitor define $(basename {} .tick) -tick {}' ';'");

    return true;
}

static bool
EnableAllTasks()
{
    HexSystemF(0, "kapacitor enable '*'");

    return true;
}

static bool
DeleteAllTasks()
{
    HexSystemF(0, "kapacitor delete tasks '*'");

    return true;
}

static bool
DefineTemplates()
{
    HexSystemF(0, "find " TPL_DIR " -name '*.tick' -exec sh -c 'kapacitor define-template $(basename {} .tick) -tick {}' ';'");

    return true;
}

static bool
RedefineHandlers()
{
    HexSystemF(0, "kapacitor delete topic-handlers events '*'");
    HexSystemF(0, "kapacitor delete topic-handlers instance-events '*'");
    HexSystemF(0, "find " HDR_DIR " -name '*.yaml' -exec sh -c 'kapacitor define-topic-handler {}' ';'");
    HexSystemF(0, "find " CFGHDR_DIR " -name '*.yaml' -exec sh -c 'kapacitor define-topic-handler {}' ';'");

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
Init()
{
    HexSetFileMode("/var/log/kapacitor/kapacitord.err", "kapacitor", "kapacitor", 0600);
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
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        return true;
    }

    return modified | s_bCubeModified | s_bNetModified |
                     G_MOD(MGMT_ADDR) | G_MOD(SHARED_ID);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = IsControl(s_eCubeRole);
    std::string myip = G(MGMT_ADDR);
    std::string sharedId = G(SHARED_ID);


    if (enabled) {
        std::vector<std::string> peerNames(0);
        std::vector<std::string> peerAddrs(0);
        if (s_ha) {
            peerNames = GetControllerPeers(s_hostname, s_ctrlHosts);
            peerAddrs = GetControllerPeers(myip, s_ctrlAddrs);
        }

        WriteConfig(peerNames, peerAddrs);
        WriteLogRotateConf(log_conf);

        SystemdCommitService(enabled, NAME);

        // Wait kapacitor to start listening port 9092
        HexUtilSystemF(0, 0, HEX_SDK " wait_for_service :: 9092 90");

        DeleteAllTasks();
        // Write task tick scritps to relay influxdb write requsts to HA peers
        WriteRelayTask(TELEGRAF_DB, TSDB_RP, peerNames);
        WriteRelayTask(TELEGRAF_DB, HC_TSDB_RP, peerNames);
        WriteRelayTask(CEPH_DB, TSDB_RP, peerNames);
        WriteRelayTask(CEPH_DB, HC_TSDB_RP, peerNames);
        WriteRelayTask(MONASCA_DB, TSDB_RP, peerNames);
        WriteRelayTask(MONASCA_DB, HC_TSDB_RP, peerNames);
        WriteRelayTask(EVENTS_DB, TSDB_RP, peerNames);
        WriteRelayTask(EVENTS_DB, HC_TSDB_RP, peerNames);
        WriteAlertExtra(s_alertExtraPrefix);

        HexLogInfo("kapacitor refresh tasks/templates/handlers");
        DefineTasks();
        EnableAllTasks();
        DefineTemplates();
        RedefineHandlers();

        HexUtilSystemF(0, 0, HEX_SDK " alert_resp_jail_start");
        HexUtilSystemF(0, 0, HEX_SDK " alert_sync_tenant");

        CronAlertCheck(s_alertChkEnabled, s_alertChkEventId, s_hostname, s_alertChkInterval);
    }
    else
        SystemdCommitService(enabled, NAME);

    return true;
}

CONFIG_MODULE(kapacitor, Init, Parse, 0, 0, Commit);

// startup sequence
CONFIG_REQUIRES(kapacitor, memcache);
CONFIG_REQUIRES(kapacitor, influxdb);

// extra tunings
CONFIG_OBSERVES(kapacitor, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(kapacitor, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(kapacitor, "/var/lib/kapacitor");
