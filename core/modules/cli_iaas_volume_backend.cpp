// CUBE SDK

#include "cli_iaas_volume_backend.hpp"

// This mode is not available in STRICT error state
CLI_MODE(
    CLI_TOP_COMMAND_IAAS,
    CLI_COMMAND_IAAS_STORAGE,
    "Work with external settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

static bool
ListExistingBackends()
{
    std::cout << "[Current Cinder Volume Backends]" << std::endl;
    const auto r = OpenstackExec("volume service list");
    if (r.exitCode == 0) {
        std::cout << r.stdoutOutput << std::endl;
    } else {
        std::cout << r.stderrOutput << std::endl;
    }
    return true;
}

static bool
ListConfiguredBackends(const ExtStorageConfig& config)
{
    return true;
}

static int
BackendListMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="list" */) {
        return CLI_INVALID_ARGS;
    }

    ListExistingBackends();

    HexPolicyManager policyManager;
    ExtStoragePolicy policy;
    if (!policyManager.load(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }
    const ExtStorageConfig config = policy.getConfig();

    ListConfiguredBackends(config);

    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_STORAGE,
    "list",
    BackendListMain,
    NULL,
    "List all external storage settings on the appliance.",
    "list");

static int
BackendCfgMain(int argc, const char** argv)
{
    if (argc > 8 /* [0]="configure", [1]=<add|delete|update>, [2]=<name>, [3~7]=<settings> */)
        return CLI_INVALID_ARGS;

    // TODO: HexLogEvent("[user] modified external storage policy via cli");
    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_STORAGE,
    "configure",
    BackendCfgMain,
    NULL,
    "Configure external storage settings.",
    "configure [<add|delete|update>] [<name>] [<driver>] [<endpoint>] [<account>] [<secret>] [<pool>]");
