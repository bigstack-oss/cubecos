// CUBE

#include <stdio.h>
#include <unistd.h>

#include <map>
#include <list>

#include <hex/log.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <cube/systemd_util.h>
#include <cube/config_file.h>
#include <cube/cluster.h>

#include "include/role_cubesys.h"

#define DELL_POWEREDGE_XR_MARKER "/etc/appliance/state/dell_poweredge_xr_detected"

#define IN_EXT      ".in"
#define CONF        "/etc/telegraf/telegraf.conf"
#define TSDB_RP     "def"
#define CTRL_CONF   "/etc/telegraf/telegraf-ctrl.conf"
#define DEV_CONF     "/etc/telegraf/telegraf-dev.conf"
#define DEV_LIST     "/var/appliance-db/device.lst"
#define IPMI_DETECT "/etc/appliance/state/ipmi_detected"

#define DEV_LINUX_CONF  "/etc/telegraf/telegraf-device-linux.conf"
#define DEV_WIN_CONF    "/etc/telegraf/telegraf-device-win.conf"

const static char NAME[] = "telegraf";

static bool s_bCubeModified = false;
static bool s_bKapacitorModified = false;

static bool s_bConfigChanged = false;

static CubeRole_e s_eCubeRole;
static Configs cfg;

// external global variables
CONFIG_GLOBAL_STR_REF(CTRL_IP);
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(KAPACITOR_ALERT_FLOW_BASE);
CONFIG_TUNING_SPEC_STR(KAPACITOR_ALERT_FLOW_UNIT);
CONFIG_TUNING_SPEC_INT(KAPACITOR_ALERT_FLOW_THRESHOLD);

// parse tunings
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_alertFlowBase, KAPACITOR_ALERT_FLOW_BASE, 2);
PARSE_TUNING_X_STR(s_alertFlowUnit, KAPACITOR_ALERT_FLOW_UNIT, 2);
PARSE_TUNING_X_INT(s_alertFlowThreshold, KAPACITOR_ALERT_FLOW_THRESHOLD, 2);

struct DeviceInfo {
    std::string hostname;
    std::string ip;
    std::string user;
    std::string pass;
    std::string proto;
    std::string role;
    std::string ping;
};

std::map<std::string, std::list<DeviceInfo>> DeviceMap;

static void DeviceInfoGet(const std::string &line, const std::string &key, std::string *value)
{
    size_t found;
    *value = "";

    if (line.find(key) != std::string::npos) {
        *value = line.substr(line.find(key) + strlen(key.c_str()));
        found = value->find(',');
        if (found != std::string::npos)
           value->erase(found, std::string::npos);  // get rid of rest after comma
        found = value->find('\n');
        if (found != std::string::npos)
           value->erase(found, std::string::npos);  // get rid of rest after newline
        found = value->find('\r');
        if (found != std::string::npos)
           value->erase(found, std::string::npos);  // get rid of rest after return
    }
}

static bool
WriteDeviceConfig()
{
    FILE *fout = fopen(DEV_CONF, "w");
    if (!fout) {
        HexLogError("Unable to write telegraf device config: %s", DEV_CONF);
        return false;
    }

    fprintf(fout, "\n");

    if (access(IPMI_DETECT, F_OK) == 0) {
        FILE *fin = fopen(IPMI_DETECT, "r");
        if (!fin) {
            HexLogError("Unable to read ipmi vendor file: %s", IPMI_DETECT);
            return false;
        }

        char *buffer = NULL;
        size_t bufSize = 0;
        if (getline(&buffer, &bufSize, fin) > 0) {
            std::string vendor = buffer;

            if (vendor.length() > 0 && vendor[vendor.length() - 1] == '\n')
                vendor.pop_back();

            fprintf(fout, "[[inputs.ipmi_sensor]]\n");
            // ipmitool sdr elist on Dell PowerEdge XR series (ex: XR4520c) can take 10+ min
            // to finish. When numerous ipmitool processes jam up at the same time, system
            // performance degrades significantly, resulting in systemd kicked out of dbus
            if (access(DELL_POWEREDGE_XR_MARKER, F_OK) == 0) {
                fprintf(fout, "interval = \"20m\"\n");
                fprintf(fout, "timeout = \"20m\"\n");
            }
            fprintf(fout, "metric_version = 2\n");
            fprintf(fout, "[inputs.ipmi_sensor.tags]\n");
            fprintf(fout, "  role = \"cube\"\n");
            fprintf(fout, "  vendor = \"%s\"\n", vendor.c_str());
            fprintf(fout, "\n");
        }

        free(buffer);
        buffer = NULL;

        fclose(fin);
    }

    if (access(DEV_LIST, F_OK) == 0) {
        DeviceMap.clear();

        FILE *fin = fopen(DEV_LIST, "r");
        if (!fin) {
            HexLogError("Unable to read device list: %s", DEV_CONF);
            return false;
        }

        char *buffer = NULL;
        size_t bufSize = 0;
        while (getline(&buffer, &bufSize, fin) > 0) {
            std::string line = buffer;

            std::string vendor;
            DeviceInfo info;
            DeviceInfoGet(line, "hostname=", &info.hostname);
            DeviceInfoGet(line, "ip=", &info.ip);
            DeviceInfoGet(line, "user=", &info.user);
            DeviceInfoGet(line, "pass=", &info.pass);
            DeviceInfoGet(line, "proto=", &info.proto);
            DeviceInfoGet(line, "role=", &info.role);
            DeviceInfoGet(line, "ping=", &info.ping);
            DeviceInfoGet(line, "vendor=", &vendor);
            if (info.role != "cube")
                DeviceMap[vendor].push_back(info);
        }

        free(buffer);
        buffer = NULL;

        fclose(fin);

        for (auto const& [vendor, list] : DeviceMap) {
            for(const auto& info : list) {
                if (info.proto != "lan" && info.proto != "lanplus")
                    continue;

                std::string config = "\"" + info.user + ":" + info.pass + "@" + info.proto + "(" + info.ip + ")\"";

                fprintf(fout, "[[inputs.ipmi_sensor]]\n");
                fprintf(fout, "servers = [%s]\n", config.c_str());
                fprintf(fout, "metric_version = 2\n");
                fprintf(fout, "[inputs.ipmi_sensor.tags]\n");
                fprintf(fout, "  vendor = \"%s\"\n", vendor.c_str());
                if (info.hostname.length())
                    fprintf(fout, "  hostname = \"%s\"\n", info.hostname.c_str());
                else
                    fprintf(fout, "  hostname = \"%s\"\n", info.ip.c_str());
                fprintf(fout, "\n");
            }
        }

        fprintf(fout, "[[inputs.exec]]\n");
        fprintf(fout, "commands = [ \"sudo /usr/sbin/hex_sdk network_device_ping\" ]\n");
        fprintf(fout, "interval = \"5m\"\n");
        fprintf(fout, "timeout = \"1m\"\n");
        fprintf(fout, "data_format = \"influx\"\n");
        fprintf(fout, "\n");
    }

    fclose(fout);

    HexSystemF(0, "cat %s >> %s", DEV_CONF, CONF);

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

static bool
ParseKapacitor(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 2);
    return true;
}

static void
NotifyKapacitor(bool modified)
{
    s_bKapacitorModified = IsModifiedTune(2);
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        s_bConfigChanged = true;
        return true;
    }

    s_bConfigChanged = modified | s_bCubeModified | s_bKapacitorModified |
                       G_MOD(CTRL_IP) | G_MOD(SHARED_ID);

    return s_bConfigChanged;
}

static bool
Init()
{
    HexSetFileMode("/dev/ipmi0", "root", "telegraf", 0660);
    HexSetFileMode("/etc/telegraf/.config/", "root", "telegraf", 0755);
    HexSetFileMode("/var/log/telegraf/telegraf.log", "telegraf", "telegraf", 0600);
    return true;
}

static bool
Commit(bool modified, int dryLevel)
{
    // TODO: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    if (s_bConfigChanged) {
        std::string ctrlIp = G(CTRL_IP);
        std::string sharedId = G(SHARED_ID);
        std::string qkafkaHosts = KafkaServers(false, sharedId, "", true);

        if (HexSystemF(0, "sed -e 's/@KAFKA_HOSTS@/%s/' %s > %s",
                       qkafkaHosts.c_str(),
                       CONF IN_EXT, CONF) != 0) {
            HexLogError("failed to update %s", CONF);
            return false;
        }

        if (HexSystemF(0, "sed -e 's/@KAFKA_HOSTS@/%s/' %s > %s",
                       qkafkaHosts.c_str(),
                       DEV_LINUX_CONF IN_EXT, DEV_LINUX_CONF) != 0) {
            HexLogError("failed to update %s", DEV_LINUX_CONF);
            return false;
        }

        if (HexSystemF(0, "sed -e 's/@KAFKA_HOSTS@/%s/' %s > %s",
                       qkafkaHosts.c_str(),
                       DEV_WIN_CONF IN_EXT, DEV_WIN_CONF) != 0) {
            HexLogError("failed to update %s", DEV_WIN_CONF);
            return false;
        }

        WriteDeviceConfig();

        if (IsControl(s_eCubeRole)) {
            if (HexSystemF(0, "sed -e 's/@BASE@/%s/' -e 's/@UNIT@/%s/' -e 's/@THRESHOLD@/%d/' %s > %s",
                           s_alertFlowBase.c_str(), s_alertFlowUnit.c_str(), s_alertFlowThreshold.newValue(),
                           CTRL_CONF IN_EXT, CTRL_CONF) != 0) {
                HexLogError("failed to update %s", CTRL_CONF);
                return false;
            }
            HexSystemF(0, "cat %s >> %s", CTRL_CONF, CONF);
        }
    }

    SystemdCommitService(true, NAME);

    return true;
}

static int
ClusterStartMain(int argc, char **argv)
{
    if (argc != 1) {
        return EXIT_FAILURE;
    }

    // FIXME: telegraf will stop running due to no kafka available
    SystemdCommitService(true, NAME);

    return EXIT_SUCCESS;
}

static void
GetLinuxConfigUsage(void)
{
    fprintf(stderr, "Usage: %s get_linux_agent_config\n", HexLogProgramName());
}

static int
GetLinuxConfigMain(int argc, char* argv[])
{
    if (argc != 1) {
        GetLinuxConfigUsage();
        return EXIT_FAILURE;
    }

    HexSystem(0, "cat", DEV_LINUX_CONF, NULL);

    return EXIT_SUCCESS;
}

static void
GetWinConfigUsage(void)
{
    fprintf(stderr, "Usage: %s get_win_agent_config\n", HexLogProgramName());
}

static int
GetWinConfigMain(int argc, char* argv[])
{
    if (argc != 1) {
        GetWinConfigUsage();
        return EXIT_FAILURE;
    }

    HexSystem(0, "cat", DEV_WIN_CONF, NULL);

    return EXIT_SUCCESS;
}

CONFIG_COMMAND(get_linux_agent_config, GetLinuxConfigMain, GetLinuxConfigUsage);
CONFIG_COMMAND(get_win_agent_config, GetWinConfigMain, GetWinConfigUsage);

CONFIG_MODULE(telegraf, Init, 0, 0, 0, Commit);

// startup sequence
CONFIG_REQUIRES(telegraf, cube_scan);
CONFIG_REQUIRES(telegraf, kafka);

// extra tunings
CONFIG_OBSERVES(telegraf, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(telegraf, kapacitor, ParseKapacitor, NotifyKapacitor);

CONFIG_TRIGGER_WITH_SETTINGS(telegraf, "cluster_start", ClusterStartMain);

CONFIG_MIGRATE(telegraf, DEV_LIST);

