// CUBE SDK

#include <sys/stat.h>

#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/log.h>
#include <hex/strict.h>
#include <hex/parse.h>
#include <hex/license.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

#define HEX_DONE "/run/bootstrap_done"
#define CUBE_DONE "/run/cube_commit_done"
#define CUBE_MODE "/etc/appliance/state/boot_mode"
#define CLUSTER_SYNC "/run/cube_cluster_synced"
#define COMMIT_LOCK "/var/run/hex_config.commit.lock"
#define COMMIT_ALL "/etc/hex_config.commit.all"

static int
BootStatusMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="status" */)
        return CLI_INVALID_ARGS;

    struct stat ms;

    if (stat(COMMIT_ALL, &ms) == 0)
        CliPrintf("two phase boot... [no]");
    else
        CliPrintf("two phase boot... [yes]");

    if (stat(HEX_DONE, &ms) != 0) {
        CliPrintf("standalone services... [booting]");
        return CLI_SUCCESS;
    }

    CliPrintf("standalone services... [ready]");
    if (stat(CUBE_DONE, &ms) == 0)
        CliPrintf("cube services... [ready]");
    else
        CliPrintf("cube services... [n/a]");

    if (stat(CLUSTER_SYNC, &ms) == 0)
        CliPrintf("cluster data... [synced]");
    else
        CliPrintf("cluster data... [unsynced]");

    if (stat(COMMIT_LOCK, &ms) == 0)
        CliPrintf("applying policy... [yes]");
    else
        CliPrintf("applying policy... [no]");

    return CLI_SUCCESS;
}

static int
BootCubeMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="bootstrap_cube" */)
        return CLI_INVALID_ARGS;

    CliPrintf("bootstrapping cube...");
    if (HexSpawn(0, HEX_CFG, "-p", "bootstrap", "standalone-done", NULL) != 0)
        CliPrintf("bootstrap failed");
    else {
        // reset boot mode to auto after manual bootstrap is done
        HexSystemF(0, "! grep -q 'one-time manual' %s 2>/dev/null || :> %s", CUBE_MODE, CUBE_MODE);
        CliPrintf("bootstrap successfully");
        CliPrintf("if this is a single node start, just run \"boot> cluster_sync\"");
        CliPrintf("if this is a cluster start, wait until bootstrap_done is done in all nodes");
        CliPrintf("and run \"cluster> start\" to sync cluster data for all nodes");
    }

    return CLI_SUCCESS;
}

static int
BootLinkCheckMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="link_check" */)
        return CLI_INVALID_ARGS;

    HexSpawn(0, HEX_SDK, "health_link_report", NULL);

    return CLI_SUCCESS;
}

static int
BootClusterSyncMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="cluster_sync" */)
        return CLI_INVALID_ARGS;

    HexSpawn(0, HEX_SDK, "-v", "cube_cluster_start", NULL);

    CliPrintf("cluster_sync successfully");

    return CLI_SUCCESS;
}

static int
BootTwoPhaseMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="two_phase_boot" [1]=<on|off> */)
        return CLI_INVALID_ARGS;

    int index = 0;
    std::string strEn;
    bool enabled = true;

    if(CliMatchCmdHelper(argc, argv, 1, "echo 'on\noff'", &index, &strEn) != CLI_SUCCESS ||
       !HexParseBool(strEn.c_str(), &enabled)) {
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_CFG, "force_commit_all", enabled ? "off" : "on", NULL);

    return CLI_SUCCESS;
}

bool
BootstrapCubeAuto()
{
    return ( HexSystemF(0, "grep -q manual %s", CUBE_MODE) != 0 ) ? true : false;
}

CLI_MODE(CLI_TOP_MODE, "boot", "Work with booting cube node.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && !BootstrapCubeAuto());

CLI_MODE_COMMAND("boot", "status", BootStatusMain, NULL,
    "show booting status.",
    "status");

CLI_MODE_COMMAND("boot", "bootstrap_cube", BootCubeMain, NULL,
    "bootstrap cube services.",
    "bootstrap_cube");

CLI_MODE_COMMAND("boot", "link_check", BootLinkCheckMain, NULL,
    "check connectivity with other nodes.",
    "link_check");

CLI_MODE_COMMAND("boot", "cluster_sync", BootClusterSyncMain, NULL,
    "fetch cluster config to local.",
    "cluster_sync");

CLI_MODE_COMMAND("boot", "two_phase_boot", BootTwoPhaseMain, NULL,
    "set two phase boot (default: on).",
    "two_phase_boot [<on|off>]");
