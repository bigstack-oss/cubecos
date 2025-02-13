// CUBE SDK

#include <hex/log.h>
#include <hex/strict.h>
#include <hex/process.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

#include <cube/cubesys.h>

static int
ResetMain(int argc, const char** argv)
{
    /*
     * [0]="reset", [1]=<volume id>
     */
    if (argc > 2)
        return CLI_INVALID_ARGS;

    std::string uuid;
    int index;

    std::string optCmd = std::string(HEX_SDK) + " os_cinder_volume_list";
    std::string descCmd = std::string(HEX_SDK) + " -v os_cinder_volume_list";

    if(CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &uuid, "Select a volume to be reset: ") != CLI_SUCCESS) {
        CliPrintf("instance name is missing or not found");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    HexSpawn(0, HEX_SDK, "os_cinder_volume_reset", uuid.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
QuotaSetMain(int argc, const char** argv)
{
    if (argc > 5 /* [0]="quota_set" [1]="domain" [2]="tenant" [3]="type" [4]="quota" */)
        return CLI_INVALID_ARGS;

    int index;
    std::string domain, tenant, type, quota;
    std::string cmd;

    cmd = std::string(HEX_SDK) + " os_list_domain_basic";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    cmd = std::string(HEX_SDK) + " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &tenant, "Select tenant: ") != CLI_SUCCESS) {
        CliPrintf("Invalid tenant");
        return CLI_INVALID_ARGS;
    }

    cmd = std::string(HEX_SDK) + " os_cinder_quota_list";
    if (CliMatchCmdHelper(argc, argv, 3, cmd, &index, &type, "Select type: ") != CLI_SUCCESS) {
        CliPrintf("Invalid quota type");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 4, "Input quota value: ", &quota) ||
        quota.length() <= 0) {
        CliPrint("quota value is required");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_cinder_quota_update", tenant.c_str(), type.c_str(), quota.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
QuotaShowMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="quota_show" [1]="domain" [2]="tenant" */)
        return CLI_INVALID_ARGS;

    int index;
    std::string domain, tenant;
    std::string cmd;

    cmd = std::string(HEX_SDK) + " os_list_domain_basic";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    cmd = std::string(HEX_SDK) + " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &tenant, "Select tenant: ") != CLI_SUCCESS) {
        CliPrintf("Invalid tenant");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_cinder_quota_show", tenant.c_str(), NULL);

    return CLI_SUCCESS;
}

// This mode is not available in STRICT error state
CLI_MODE("iaas", "volume",
    "Work with the IaaS volume settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("volume", "reset", ResetMain, NULL,
        "Reset volume state to available for attaching.",
        "reset [<volume id>]");

CLI_MODE_COMMAND("volume", "quota_set", QuotaSetMain, NULL,
        "Set volume quota for a tenant.",
        "quota_set [<domain>] [<tenant>] [<type>] [<quota>]");

CLI_MODE_COMMAND("volume", "quota_show", QuotaShowMain, NULL,
        "Show volume quota for a tenant.",
        "quota_show [<domain>] [<tenant>]");

