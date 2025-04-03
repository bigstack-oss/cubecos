// CUBE

#include <limits.h>
#include <unistd.h>
#include <net/if.h>

#include <hex/log.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/string_util.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/dryrun.h>
#include <hex/logrotate.h>

#include <cube/systemd_util.h>

#include "include/role_cubesys.h"

#define IPTABLES_SERVICEINT "/etc/appliance/state/iptables_service-int"
#define AS_CLOUD_DEF 3
#define AS_EDGE_DEF 6

static const char HOSTS[] = "/etc/hosts";

//static const char GENCERTS_CMD[] = "/var/www/gencerts.sh";
//static const char SRV_KEY[] = "/var/www/certs/server.key";
//static const char SRV_CRT[] = "/var/www/certs/server.cert";
static const char SSH_CLIENT_CONFIG[] = "/etc/ssh/ssh_config";
static const char SSH_DIR[] = "/root/.ssh";
static const char KEYFILE[] = "/root/.ssh/id_rsa";
static const char KEYFILE_PUB[] = "/root/.ssh/id_rsa.pub";
static const char AUTHORIZED_KEYS[] = "/root/.ssh/authorized_keys";

static const char IPTABLES_RULESET[] = "/etc/sysconfig/iptables";

static const char ALERT_LEVEL[] = "/etc/alert.level";

static const char MODPROBE_USB_CONFIG[] = "/etc/modprobe.d/usb.conf";

static bool s_bHostsChanged = false;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("cube-health", "/var/log/health_*.log", DAILY, 128, 0, true);

// private tunings
CONFIG_TUNING_STR(CUBESYS_ROLE, "cubesys.role", TUNING_UNPUB, "Set the role of cube appliance.", "undef", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_DOMAIN, "cubesys.domain", TUNING_UNPUB, "Set the domain of cube appliance.", DOMAIN_DEF, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_REGION, "cubesys.region", TUNING_UNPUB, "Set the region of cube appliance.", REGION_DEF, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_CONTROLLER, "cubesys.controller", TUNING_UNPUB, "Set controller.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_CONTROLLER_IP, "cubesys.controller.ip", TUNING_UNPUB, "Set controller IP address.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_MGMT, "cubesys.management", TUNING_UNPUB, "Set management interface.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_PROVIDER, "cubesys.provider", TUNING_UNPUB, "Set provider interface.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_OVERLAY, "cubesys.overlay", TUNING_UNPUB, "Set overlay network interface.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_STORAGE, "cubesys.storage", TUNING_UNPUB, "Set storage network interface.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_SEED, "cubesys.seed", TUNING_UNPUB, "Set Cube cluster secret seed.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_MGMT_CIDR, "cubesys.mgmt.cidr", TUNING_UNPUB, "Set Cube cluster management CIDR.", MGMT_CIDR_DEF, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_CONTROL_VIP, "cubesys.control.vip", TUNING_UNPUB, "Set cluster virtual ip.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_CONTROL_HOSTS, "cubesys.control.hosts", TUNING_UNPUB, "Set control group hostname [hostname,hostname,...].", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_CONTROL_ADDRS, "cubesys.control.addrs", TUNING_UNPUB, "Set control group address [ip,ip,...].", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_STORAGE_HOSTS, "cubesys.storage.hosts", TUNING_UNPUB, "Set storage group hostname [hostname,hostname,...].", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_STORAGE_ADDRS, "cubesys.storage.addrs", TUNING_UNPUB, "Set storage group address [ip,ip,...].", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_BOOL(CUBESYS_HA, "cubesys.ha", TUNING_UNPUB, "Set true for indicate a HA setup.", false);
CONFIG_TUNING_BOOL(CUBESYS_SALTKEY, "cubesys.saltkey", TUNING_UNPUB, "Set true for enabling key scrambling.", false);
CONFIG_TUNING_STR(CUBESYS_EXTERNAL, "cubesys.external", TUNING_UNPUB, "Set external IP/Domain.", "", ValidateRegex, DFT_REGEX_STR);

// public tunings
CONFIG_TUNING_STR(CUBESYS_PROVIDER_EXTRA, "cubesys.provider.extra", TUNING_PUB, "Set extra provider interfaces ('pvd-' prefix and <= 15 chars) [IF.2:pvd-xxx,eth2:pvd-yyy,...].", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_INT(CUBESYS_LOG_DEFAULT_RP, "cubesys.log.default.retention", TUNING_PUB, "Set log file retention policy in days.", 14, 0, 365);
CONFIG_TUNING_INT(CUBESYS_CONNTABLE_MAX, "cubesys.conntable.max", TUNING_PUB, "Set max connection table size.", 262144, 0, INT_MAX);
CONFIG_TUNING_INT(CUBESYS_ALERT_LEVEL, "cubesys.alert.level", TUNING_PUB, "Set health alert sensible level. (0: default, 1: highly sensitive)", 0, 0, INT_MAX);
CONFIG_TUNING_INT(CUBESYS_ALERT_LEVEL_SERVICE, "cubesys.alert.level.%s", TUNING_PUB, "Set health alert sensible level for service %s. (0: default, 1: highly sensitive)", 0, 0, INT_MAX);
CONFIG_TUNING_BOOL(CUBESYS_PROBEUSB, "cubesys.probeusb", TUNING_PUB, "Set true to allow loading USB drivers.", false);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);

// parse tunings
PARSE_TUNING_STR(s_cubeRole, CUBESYS_ROLE);
PARSE_TUNING_STR(s_cubeDomain, CUBESYS_DOMAIN);
PARSE_TUNING_STR(s_cubeRegion, CUBESYS_REGION);
PARSE_TUNING_STR(s_controller, CUBESYS_CONTROLLER);
PARSE_TUNING_STR(s_controllerIp, CUBESYS_CONTROLLER_IP);
PARSE_TUNING_STR(s_external, CUBESYS_EXTERNAL);
PARSE_TUNING_STR(s_mgmt, CUBESYS_MGMT);
PARSE_TUNING_STR(s_provider, CUBESYS_PROVIDER);
PARSE_TUNING_STR(s_overlay, CUBESYS_OVERLAY);
PARSE_TUNING_STR(s_storage, CUBESYS_STORAGE);
PARSE_TUNING_STR(s_seed, CUBESYS_SEED);
PARSE_TUNING_STR(s_mgmtCidr, CUBESYS_MGMT_CIDR);
PARSE_TUNING_STR(s_ctrlHosts, CUBESYS_CONTROL_HOSTS);
PARSE_TUNING_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS);
PARSE_TUNING_STR(s_strgHosts, CUBESYS_STORAGE_HOSTS);
PARSE_TUNING_STR(s_strgAddrs, CUBESYS_STORAGE_ADDRS);
PARSE_TUNING_STR(s_ctrlVip, CUBESYS_CONTROL_VIP);
PARSE_TUNING_BOOL(s_ha, CUBESYS_HA);
PARSE_TUNING_BOOL(s_saltKey, CUBESYS_SALTKEY);
PARSE_TUNING_BOOL(s_probeUsb, CUBESYS_PROBEUSB);
PARSE_TUNING_INT(s_logDefRp, CUBESYS_LOG_DEFAULT_RP);
PARSE_TUNING_INT(s_connMax, CUBESYS_CONNTABLE_MAX);
PARSE_TUNING_INT(s_alertLvl, CUBESYS_ALERT_LEVEL);
PARSE_TUNING_INT_MAP(s_alertLvlMap, CUBESYS_ALERT_LEVEL_SERVICE);

static bool
WriteSshConfig(void)
{
    FILE *fout = fopen(SSH_CLIENT_CONFIG, "w");
    if (!fout) {
        HexLogError("Unable to write ssh client config: %s", SSH_CLIENT_CONFIG);
        return false;
    }

    fprintf(fout, "CheckHostIP no\n");
    fprintf(fout, "StrictHostKeyChecking no\n");
    fprintf(fout, "UserKnownHostsFile /dev/null\n");
    fclose(fout);

    return true;
}

static bool
WriteModprobeUsbConfig(void)
{
    FILE *fout = fopen(MODPROBE_USB_CONFIG, "w");
    if (!fout) {
        HexLogError("Unable to write modprobe USB config: %s", MODPROBE_USB_CONFIG);
        return false;
    }

    bool probeUsb = s_probeUsb;
    if (probeUsb == true) {
        // empty the config file
        fclose(fout);
        // load the drivers
        HexUtilSystemF(0, 0, "/usr/sbin/modprobe usb_storage 2>/dev/null");
        HexUtilSystemF(0, 0, "/usr/sbin/modprobe uas 2>/dev/null");
    } else {
        // block drivers to prevent auto-loading
        fprintf(fout, "blacklist uas\n");
        fprintf(fout, "blacklist usb_storage\n");
        fprintf(fout, "install usb_storage /bin/true\n");
        fclose(fout);
        // unmount USB devices
        HexUtilSystemF(0, 0, "/bin/sync ; /bin/umount %s >/dev/null 2>&1", USB_MNT_DIR);
        // remove the drivers
        HexUtilSystemF(0, 0, "/usr/sbin/modprobe -r uas 2>/dev/null");
        HexUtilSystemF(0, 0, "/usr/sbin/modprobe -r usb_storage 2>/dev/null");
    }

    return true;
}

static bool
WriteIptablesConfig()
{
    FILE *fout = fopen(IPTABLES_RULESET, "w");
    if (!fout) {
        HexLogError("Unable to write iptables ruleset: %s", IPTABLES_RULESET);
        return false;
    }

    fprintf(fout, "*filter\n");
    fprintf(fout, ":INPUT ACCEPT [0:0]\n");
    fprintf(fout, ":FORWARD ACCEPT [0:0]\n");
    fprintf(fout, ":OUTPUT ACCEPT [0:0]\n");
    fprintf(fout, ":SERVICE-INT - [0:0]\n");
    fprintf(fout, "-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT\n");
    fprintf(fout, "-A INPUT -j SERVICE-INT\n");
    fprintf(fout, "-A INPUT -m state --state NEW -j ACCEPT\n");
    fprintf(fout, "-A INPUT -p icmp -j ACCEPT\n");
    fprintf(fout, "-A INPUT -p udp -j ACCEPT\n");
    fprintf(fout, "COMMIT\n");

    fclose(fout);

    return true;
}

static bool
UpdateHosts(const char* key, const char* strHosts, const char* strAddrs)
{
    if (strlen(strHosts) == 0 || strlen(strAddrs) == 0)
        return true;

    auto hosts = hex_string_util::split(strHosts, ',');
    auto addrs = hex_string_util::split(strAddrs, ',');

    HexSystemF(0, "sed -i '/# %s-start/,/# %s-end/d' %s", key, key, HOSTS);
    HexSystemF(0, "echo '# %s-start' >> %s", key, HOSTS);
    for (size_t i = 0 ; i < hosts.size() ; i++) {
        HexSystemF(0, "echo '%s    %s' >> %s", addrs[i].c_str(), hosts[i].c_str(), HOSTS);
    }
    HexSystemF(0, "echo '# %s-end' >> %s", key, HOSTS);

    return true;
}

static bool
Init()
{
    // Cert and key are generated by config_clsuter module
    // if (access(SRV_KEY, F_OK) != 0 || access(SRV_CRT, F_OK) != 0) {
    //     if (HexUtilSystemF(0, 0, GENCERTS_CMD) != 0) {
    //         HexLogError("failed to generate %s and %s", SRV_KEY, SRV_CRT);
    //         return false;
    //     }
    // }

    // handle outside file existence check in the case of firmware upgrade
    // HexSetFileMode(SRV_KEY, "root", "root", 0644);
    // HexSetFileMode(SRV_CRT, "root", "root", 0644);

    if (HexMakeDir(SSH_DIR, "root", "root", 0755) != 0) {
        HexLogError("failed to mkdir %s", SSH_DIR);
        return false;
    }

    return true;
}

static bool
CheckIfname(const char *name, bool isLabel)
{
    /* These checks mimic kernel checks in dev_valid_name */
    if (*name == '\0')
        return false;

    /* less than IFNAMSIZ(16) */
    if (strlen(name) >= IFNAMSIZ)
        return false;

    /* label name must start with pvd- */
    if (isLabel && strstr(name, "pvd-") == NULL)
        return false;

    /* invalid if it contains '/' or space */
    while (*name) {
        if (*name == '/' || isspace(*name))
            return false;
        ++name;
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

    // advanced check
    if (strcmp(name, "cubesys.provider.extra") == 0) {
        auto providers = hex_string_util::split(std::string(value), ',');
        for (auto p : providers) {
            auto comp = hex_string_util::split(p, ':');
            if (comp.size() != 2) {
                HexLogError("Invalid settings value \"%s\" = \"%s\"", name, value);
                r = false;
            }
            if (!CheckIfname(comp[0].c_str(), false) || !CheckIfname(comp[1].c_str(), true)) {
                HexLogError("Bad device name or provider name \"%s\" = \"%s\"", name, value);
                r = false;
            }
        }
    }

    return r;
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        s_bHostsChanged = true;
        return true;
    }

    s_bHostsChanged = modified;

    return s_bHostsChanged;
}

static bool
Commit(bool modified, int dryLevel)
{
    // TODO: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsBootstrap())
        HexUtilSystemF(0, 0, HEX_SDK " gpu_service_config");

    if (IsUndef(GetCubeRole(s_cubeRole)) || !CommitCheck(modified, dryLevel))
        return true;

    struct stat ms;

    if (s_bHostsChanged) {
        if (ControlReq(GetCubeRole(s_cubeRole)))
            UpdateHosts("controller", s_controller.c_str(), s_controllerIp.c_str());
        else
            UpdateHosts("controller", s_controller.c_str(), s_ctrlVip.c_str());

        if (s_ha)
            UpdateHosts("control-group", s_ctrlHosts.c_str(), s_ctrlAddrs.c_str());
    }

    WriteDefLogRotateConf(s_logDefRp);

    // only print kernel log of level 0 & 1 (KERN_EMERG & KERN_ALERT) on console
    HexUtilSystemF(0, 0, "/sbin/sysctl -e -w kernel.printk=2");

    // deprecated drivers
    //HexUtilSystemF(0, 0, "/sbin/modprobe ip_tables");
    //HexUtilSystemF(0, 0, "/sbin/modprobe ip6_tables");
    HexUtilSystemF(0, 0, "/sbin/modprobe br_netfilter");

    HexUtilSystemF(0, 0, "/sbin/sysctl -e -w net.ipv4.ip_forward=1");
    HexUtilSystemF(0, 0, "/sbin/sysctl -e -w net.ipv4.conf.all.rp_filter=0");
    HexUtilSystemF(0, 0, "/sbin/sysctl -e -w net.ipv4.conf.default.rp_filter=0");
    HexUtilSystemF(0, 0, "/sbin/sysctl -e -w net.bridge.bridge-nf-call-iptables=1");
    HexUtilSystemF(0, 0, "/sbin/sysctl -e -w net.bridge.bridge-nf-call-ip6tables=1");
    HexUtilSystemF(0, 0, "/sbin/sysctl -e -w net.ipv4.ip_nonlocal_bind=1");
    HexUtilSystemF(0, 0, "/sbin/sysctl -e -w net.netfilter.nf_conntrack_max=%d", s_connMax.newValue());
    HexUtilSystemF(0, 0, "/usr/bin/ulimit -n 102400");

    HexSystemF(0, "rm -f %s*", ALERT_LEVEL);

    int alertLvl = s_alertLvl;
    if (alertLvl == 0) {
        if (IsEdge(GetCubeRole(s_cubeRole)))
            alertLvl = AS_EDGE_DEF;
        else
            alertLvl = AS_CLOUD_DEF;
    }
    HexSystemF(0, "echo %d > %s", alertLvl, ALERT_LEVEL);

    for (auto it = s_alertLvlMap.begin(); it != s_alertLvlMap.end(); ++it) {
        if ((int)it->second > 0)
            HexSystemF(0, "echo %d > %s.%s", (int)it->second, ALERT_LEVEL, it->first.c_str());
    }

    WriteIptablesConfig();
    //HexUtilSystemF(0, 0, "/usr/sbin/iptables-restore %s", IPTABLES_RULESET);

    if(stat(KEYFILE, &ms) != 0) {
        // https://github.com/cornfeedhobo/ssh-keydgen
        HexUtilSystemF(0, 0, "echo %s | /usr/sbin/ssh-keydgen -t rsa -f %s", s_seed.c_str(), KEYFILE);
        HexUtilSystemF(0, 0, "cat %s >> %s", KEYFILE_PUB, AUTHORIZED_KEYS);
        WriteSshConfig();
        HexSetFileMode(KEYFILE, "root", "root", 0600);
        HexSetFileMode(KEYFILE_PUB, "root", "root", 0600);
        HexSetFileMode(AUTHORIZED_KEYS, "root", "root", 0644);
    }

    WriteModprobeUsbConfig();
    WriteLogRotateConf(log_conf);
    HexUtilSystemF(0, 0, "touch %s", IPTABLES_SERVICEINT);

    return true;
}

static void
SdkRunUsage(void)
{
    fprintf(stderr, "Usage: %s sdk_run <command>\n", HexLogProgramName());
}

static int
SdkRunMain(int argc, char* argv[])
{
    if (argc == 0) {
        SdkRunUsage();
        return EXIT_FAILURE;
    }

    std::vector<const char *> args;
    args.push_back(HEX_SDK);

    for (int i = 1 ; i < argc ; i++) {
        args.push_back(argv[i]);
    }

    args.push_back(NULL);

    HexSpawnV(0, (char *const *)&args[0]);

    return EXIT_SUCCESS;
}

static void
SdkHealthUsage(void)
{
    fprintf(stderr, "Usage: %s sdk_health <component>\n", HexLogProgramName());
}

static int
SdkHealthMain(int argc, char* argv[])
{
    if (argc != 2) {
        SdkHealthUsage();
        return EXIT_FAILURE;
    }

    std::string subcmd = "health_" + std::string(argv[1]) + "_check";
    std::vector<const char *> args;

    args.push_back(HEX_SDK);
    args.push_back(subcmd.c_str());
    args.push_back(NULL);

    int ret = HexExitStatus(HexSpawnV(0, (char *const *)&args[0]));
    if (ret == 0)
        printf("health=ok\n");
    else
        printf("health=nook\n");
    printf("error=%d\n", ret);

    return EXIT_SUCCESS;
}

static bool
MigrateMain(const char * prevVersion, const char * prevRootDir)
{
    HexSystemF(0, HEX_SDK " migrate_prepare");
    return true;
}

CONFIG_COMMAND(sdk_run, SdkRunMain, SdkRunUsage);
CONFIG_COMMAND(sdk_health, SdkHealthMain, SdkHealthUsage);

CONFIG_MODULE(cubesys, Init, Parse, 0, 0, Commit);

CONFIG_FIRST(cubesys);

CONFIG_SUPPORT_COMMAND(HEX_SDK " support_log_archive $HEX_SUPPORT_DIR");
CONFIG_SUPPORT_COMMAND(HEX_SDK " cube_stats");
CONFIG_SUPPORT_COMMAND(HEX_SDK " cube_oom_stats");
CONFIG_SUPPORT_COMMAND(HEX_SDK " cube_disk_stats /var/lib /var/log /var/support /var/update");
CONFIG_SUPPORT_COMMAND(HEX_CLI " -c boot status");
CONFIG_SUPPORT_COMMAND(HEX_CLI " -c cluster check");
CONFIG_SUPPORT_COMMAND_TO_FILE(HEX_CLI " -c cluster health", "/tmp/health_report.txt");

CONFIG_MIGRATE(cubesys, MigrateMain);
//CONFIG_MIGRATE(cubesys, SRV_KEY);
//CONFIG_MIGRATE(cubesys, SRV_CRT);
CONFIG_MIGRATE(cubesys, SSH_CLIENT_CONFIG);
CONFIG_MIGRATE(cubesys, AUTHORIZED_KEYS);

CONFIG_MODULE(standalone, 0, 0, 0, 0, 0);
CONFIG_REQUIRES(standalone, time);
CONFIG_REQUIRES(standalone, sshd);

