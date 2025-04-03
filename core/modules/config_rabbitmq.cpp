// CUBE

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/filesystem.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>

#include <cube/cluster.h>
#include <cube/systemd_util.h>

#include "include/role_cubesys.h"

#define CONTROL_FMT "env LANG=en_US.utf8 HOSTNAME=%s /usr/sbin/rabbitmqctl "

const static char NAME[] = "rabbitmq-server";
const static char USER[] = "rabbitmq";
const static char GROUP[] = "rabbitmq";
const static char CONF[] = "/etc/rabbitmq/rabbitmq.conf";
const static char ENV[] = "/etc/rabbitmq/rabbitmq-env.conf";
const static char CONTROL[] = "env LANG=en_US.utf8 /usr/sbin/rabbitmqctl";
const static char COOKIE_PATH[] = "/var/lib/rabbitmq/.erlang.cookie";
const static char GUEST_PASS[] = "gr4mPFndR82Ln4gk";
const static char OPENSTACK_PASS[] = "39H4Heu1pEh1amat";
const static char ERLANG_COOKIE[] = "ULFLGIAUDLQJKAWMVPMA";
const static char SETUP_MARK[] = "/etc/appliance/state/rabbitmq_cluster_done";

static ConfigString s_hostname;

static bool s_bNetModified = false;
static bool s_bCubeModified = false;

static bool s_bGuestPassChanged = false;
static bool s_bOpenstackPassChanged = false;

static CubeRole_e s_eCubeRole;

// external global variables
CONFIG_GLOBAL_BOOL_REF(IS_MASTER);
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);

// private tunings
CONFIG_TUNING_BOOL(RABBITMQ_ENABLED, "rabbitmq.enabled", TUNING_UNPUB, "Set to true to enable rabbitmq.", true);
CONFIG_TUNING_STR(RABBITMQ_GUEST_PASSWD, "rabbitmq.guest.password", TUNING_UNPUB, "Set rabbitmq guest password.", GUEST_PASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(RABBITMQ_OPENSTACK_PASSWD, "rabbitmq.openstack.password", TUNING_UNPUB, "Set rabbitmq openstack password.", OPENSTACK_PASS, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(RABBITMQ_COOKIE, "rabbitmq.cookie", TUNING_UNPUB, "Set rabbitmq erlang cookie.", ERLANG_COOKIE, ValidateRegex, DFT_REGEX_STR);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_HOSTS);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, RABBITMQ_ENABLED);
PARSE_TUNING_STR(s_guestPass, RABBITMQ_GUEST_PASSWD);
PARSE_TUNING_STR(s_mqPass, RABBITMQ_OPENSTACK_PASSWD);
PARSE_TUNING_STR(s_cookie, RABBITMQ_COOKIE);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_ctrlHosts, CUBESYS_CONTROL_HOSTS, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);

static bool
WriteConfig(const std::string& myip)
{
    FILE *fout = fopen(ENV, "w");
    if (!fout) {
        HexLogError("Unable to write %s env: %s", NAME, ENV);
        return false;
    }

    fprintf(fout, "#NODENAME=rabbit@$HOSTNAME\n");
    fprintf(fout, "CONFIG_FILE=/etc/rabbitmq/rabbitmq.conf\n");
    fprintf(fout, "NODE_IP_ADDRESS=%s\n", myip.c_str());
    fprintf(fout, "NODE_PORT=5672\n");

    fclose(fout);

    fout = fopen(CONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s config: %s", NAME, CONF);
        return false;
    }

    fprintf(fout, "cluster_partition_handling = pause_minority\n");

    fclose(fout);

    return true;
}

static bool
CreateCookie(const std::string& cookie)
{
    if (!IsControl(s_eCubeRole))
        return true;

    FILE *fout = fopen(COOKIE_PATH, "w");
    if (!fout) {
        HexLogError("Unable to write %s cookie: %s", NAME, COOKIE_PATH);
        return false;
    }

    fprintf(fout, "%s", cookie.c_str());

    if(HexSetFileMode(COOKIE_PATH, USER, GROUP, 0600) != 0) {
        HexLogError("Unable to set file %s mode/permission", COOKIE_PATH);
        return false;
    }

    fclose(fout);

    return true;
}

// depends on rabbitmq (called inside commit())
static bool
SetupCheck(const std::string& mqPass, const std::string& hostname)
{
    if (!IsControl(s_eCubeRole))
        return true;

    if (HexSystemF(0, CONTROL_FMT "list_users | grep -q openstack", hostname.c_str()) != 0) {
        HexSystemF(0, CONTROL_FMT "add_user openstack %s >/dev/null", hostname.c_str(), mqPass.c_str());
        HexSystemF(0, CONTROL_FMT "set_permissions openstack \".*\" \".*\" \".*\" >/dev/null", hostname.c_str());
    }

    HexSystemF(0, "env LANG=en_US.utf8 HOSTNAME=%s /usr/sbin/rabbitmq-plugins enable rabbitmq_management >/dev/null", hostname.c_str());

    return true;
}

static bool
UpdatePass(std::string user, std::string password, const std::string& hostname)
{
    if (!IsControl(s_eCubeRole))
        return true;

    if (HexSystemF(0, CONTROL_FMT "change_password %s %s >/dev/null", hostname.c_str(), user.c_str(), password.c_str()) != 0) {
        HexLogError("failed to update rabbitmq %s password", user.c_str());
        return false;
    }

    HexLogInfo("RabbitMQ %s password has been updated", user.c_str());

    return true;
}

static bool
IsRunning(const std::string& hostname)
{
    if (HexSystemF(0, CONTROL_FMT "status >/dev/null 2>&1", hostname.c_str()) != 0) {
        return false;
    }

    return true;
}

static bool
IsReady(int timeout, const std::string& hostname)
{
    int delay = 0;
    while (delay < timeout) {
        if (IsRunning(hostname))
            break;
        sleep(1);
        delay++;
    }

    if (delay >= timeout)
        return false;

    return true;
}

static bool
CommitRabbitMQ(const bool enabled, const bool ha, const std::string& hostname, const std::string& ctrlHosts)
{
    if (!SystemdCommitService(enabled, NAME, true)) {
        HexLogInfo("force %s bootstrap - removing data (CAUTION)", NAME);
        HexSystemF(0, "rm -rf /var/lib/rabbitmq/mnesia/*");
        SystemdCommitService(enabled, NAME, true);
    }

    // the message queue service typically runs on the controller node
    if (enabled) {
        if (!IsReady(30, hostname)) {
            HexLogError("failed in checking rabbitmq server status");
            return false;
        }

        struct stat ms;
        if (ha && stat(SETUP_MARK, &ms) != 0) {
            bool isMaster = G(IS_MASTER);
            if (isMaster && access(CONTROL_REJOIN, F_OK) != 0) {
                // Each exchange or queue will have at most one policy matching
                HexUtilSystemF(0, 0, CONTROL_FMT "set_policy ha-all \".*\" '{\"expires\": 86400, \"ha-mode\": \"all\", \"ha-sync-mode\": \"automatic\"}' --apply-to all --priority 0", hostname.c_str());

                std::vector<std::string> peers = GetControllerPeers(hostname, ctrlHosts);
                for (auto & p : peers) {
                    HexUtilSystemF(0, 0, CONTROL_FMT "forget_cluster_node rabbit@%s", hostname.c_str(), p.c_str());
                }
            }
            else {
                std::string master = GetControllerPeers(s_hostname, ctrlHosts)[0];
                if (access(CONTROL_REJOIN, F_OK) == 0) {
                    // forget myself from peer node
                    HexUtilSystemF(0, 0, "ssh root@%s %s -n rabbit@%s stop_app 2>/dev/null",
                                         master.c_str(), CONTROL, hostname.c_str());
                    HexUtilSystemF(0, 0, "ssh root@%s %s forget_cluster_node rabbit@%s 2>/dev/null",
                                         master.c_str(), CONTROL, hostname.c_str());
                }

                HexUtilSystemF(0, 0, CONTROL_FMT "stop_app", hostname.c_str());
                HexUtilSystemF(0, 0, "systemctl start rabbitmq-server");
                HexUtilSystemF(0, 0, CONTROL_FMT "join_cluster rabbit@%s", hostname.c_str(), master.c_str());
                HexUtilSystemF(0, 0, CONTROL_FMT "start_app", hostname.c_str());
            }
            HexSystemF(0, "touch %s", SETUP_MARK);
        }
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
        s_bGuestPassChanged = true;
        s_bOpenstackPassChanged = true;
        return true;
    }

    s_bGuestPassChanged = s_guestPass.modified() | s_bCubeModified;

    s_bOpenstackPassChanged = s_mqPass.modified() | s_bCubeModified;

    // rabbitmqctl refers to the current hostname to find service
    // "rabbitmqctl stop" must be called before hostname updated
    if (s_bNetModified) {
        s_bGuestPassChanged = true;
        s_bOpenstackPassChanged = true;
        SystemdCommitService(false, NAME, true);
        // todo: remove old dbs under /var/lib/rabbitmq/mnesia
    }

    return modified | s_bNetModified | s_bCubeModified | G_MOD(MGMT_ADDR);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = IsControl(s_eCubeRole) && s_enabled.newValue();

    std::string myip = G(MGMT_ADDR);
    std::string guestPass = GetSaltKey(s_saltkey, s_guestPass.newValue(), s_seed.newValue());
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass.newValue(), s_seed.newValue());
    std::string cookie = GetSaltKey(s_saltkey, s_cookie.newValue(), s_seed.newValue());

    if (s_ha)
        CreateCookie(cookie);

    WriteConfig(myip);
    CommitRabbitMQ(enabled, s_ha, s_hostname, s_ctrlHosts);

    if (s_bGuestPassChanged | s_bOpenstackPassChanged) {
        // FIXME: call change_password right after server start
        //        would cause rabbitmq-server to crash. WTF?!
        sleep(12);
    }

    SetupCheck(mqPass, s_hostname);

    if (s_bGuestPassChanged)
        UpdatePass("guest", guestPass, s_hostname);

    if (s_bOpenstackPassChanged)
        UpdatePass("openstack", mqPass, s_hostname);

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_rabbitmq\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    bool enabled = IsControl(s_eCubeRole) && s_enabled.newValue();
    std::string mqPass = GetSaltKey(s_saltkey, s_mqPass.newValue(), s_seed.newValue());
    CommitRabbitMQ(enabled, s_ha, s_hostname.newValue(), s_ctrlHosts.newValue());
    SetupCheck(mqPass, s_hostname);

    return EXIT_SUCCESS;
}

static void
StatusUsage(void)
{
    fprintf(stderr, "Usage: %s status_rabbitmq\n", HexLogProgramName());
}

static int
StatusMain(int argc, char* argv[])
{
    if (argc != 1) {
        StatusUsage();
        return EXIT_FAILURE;
    }

    HexSystemF(0, "%s --formatter json cluster_status", CONTROL);

    return EXIT_SUCCESS;
}

static void
GPassUsage(void)
{
    fprintf(stderr, "Usage: %s rabbitmq_guest_password\n", HexLogProgramName());
}

static int
GPassMain(int argc, char* argv[])
{
    if (argc != 1) {
        StatusUsage();
        return EXIT_FAILURE;
    }

    std::string guestPass = GetSaltKey(s_saltkey, s_guestPass.newValue(), s_seed.newValue());
    printf("%s\n", guestPass.c_str());

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(rabbitmq_guest_password, GPassMain, GPassUsage);
CONFIG_COMMAND(status_rabbitmq, StatusMain, StatusUsage);
CONFIG_COMMAND_WITH_SETTINGS(restart_rabbitmq, RestartMain, RestartUsage);

CONFIG_MODULE(rabbitmq, 0, Parse, 0, 0, Commit);
CONFIG_REQUIRES(rabbitmq, cluster);

// extra tunings
CONFIG_OBSERVES(rabbitmq, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(rabbitmq, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(rabbitmq, SETUP_MARK);
CONFIG_MIGRATE(rabbitmq, "/var/lib/rabbitmq");

CONFIG_SUPPORT_COMMAND("rabbitmqctl status");
CONFIG_SUPPORT_COMMAND("rabbitmqctl list_queues name pid synchronised_slave_pids");

