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
BootManualMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="switch_to_manual" */)
        return CLI_INVALID_ARGS;

    int index;
    std::string value;

    if (CliMatchCmdHelper(argc, argv, 1, "echo -e 'one-time manual\nalways manual'", &index, &value, "Switch to manual bootstrap mode:") != CLI_SUCCESS) {
        CliPrintf("Unknown action");
        return CLI_INVALID_ARGS;
    }

    if (CliReadConfirmation()) {
        HexSystemF(0, "[ -e %s ] && kill `cat %s` 2>/dev/null ; echo %s > %s", CUBE_MODE, CUBE_MODE, value.c_str(), CUBE_MODE);
        CliPrintf("Exit current CLI and log in again as admin to see changes in effect");
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

bool
BootstrapCubeManual()
{
    return ( HexSystemF(0, "grep -q manual %s", CUBE_MODE) == 0 ) ? true : false;
}

CLI_MODE(CLI_TOP_MODE, "boot_mode", "Work with auto or manual mode to boot cube node.",
	 !HexStrictIsErrorState() && !FirstTimeSetupRequired() && !BootstrapCubeManual());

CLI_MODE_COMMAND("boot_mode", "status", BootStatusMain, NULL,
    "show booting status.",
    "status");

CLI_MODE_COMMAND("boot_mode", "manual", BootManualMain, NULL,
		 "switch to manual bootstrap CLI options.",
		 "switch_to_manual");

CLI_MODE_COMMAND("boot_mode", "link_check", BootLinkCheckMain, NULL,
    "check connectivity with other nodes.",
    "link_check");
