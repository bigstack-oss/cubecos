// CUBE SDK

#include "cli_iaas_volume_backend.hpp"

// This mode is not available in STRICT error state
CLI_MODE(
    CLI_TOP_COMMAND_IAAS,
    CLI_COMMAND_IAAS_STORAGE,
    "Work with external settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

static void
listExistingBackends()
{
    const std::vector<ExistingBackend> backends = GetExistingBackends();

    // output to the terminal
    std::cout << "[Current Cinder Volume Backends]" << std::endl;
    for (const ExistingBackend& b : backends) {
        std::cout << "  Host: " << b.host << std::endl;
        std::cout << "  Zone: " << b.zone << std::endl;
        std::cout << "  Status: " << b.status << std::endl;
        std::cout << "  State: " << b.state << std::endl;
        std::cout << "  Updated At: " << b.updatedAt << std::endl;
        std::cout << std::endl;
    }
}

static bool
listConfiguredBackends()
{
    HexPolicyManager policyManager;
    ExtStoragePolicy policy;
    if (!policyManager.load(policy)) {
        return false;
    }

    const ExtStorageConfig config = policy.getConfig();

    std::cout << "[Configured Cinder Volume Backends]" << std::endl;

    std::cout << "  Backends" << std::endl;
    for (const std::string& b : config.storageBackends) {
        std::cout << "    - " << b << std::endl;

        const std::vector<IniSection> backendConfig = GetConfiguredBackendDetails(b);
        for (const IniSection& section : backendConfig) {
            std::cout << "      [" << section.header << "]" << std::endl;

            for (const std::pair<std::string, std::string> setting : section.settings) {
                std::cout << "        " << setting.first << ": " << setting.second << std::endl;
            }
        }
    }

    std::cout << "  Default Volume Type: " << config.volumeTypeDefault << std::endl;

    std::cout << "  Image Use Multipath: ";
    if (config.imageUseMultipath) {
        std::cout << "true";
    } else {
        std::cout << "false";
    }
    std::cout << std::endl;

    std::cout << "  Image Enforce Multipath: ";
    if (config.imageEnforceMultipath) {
        std::cout << "true";
    } else {
        std::cout << "false";
    }
    std::cout << std::endl;

    return true;
}

static int
BackendListMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="list" */) {
        return CLI_INVALID_ARGS;
    }

    listExistingBackends();

    if (!listConfiguredBackends()) {
        return CLI_UNEXPECTED_ERROR;
    }

    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_STORAGE,
    "list",
    BackendListMain,
    NULL,
    "List all external storage settings on the appliance.",
    "list");

static void
listModels()
{
    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        {},
        HEX_SDK " cinder_get_models");
    if (r.exitCode != 0) {
        std::cerr << "Error: " << r.stderrOutput << std::endl;
        return;
    }

    const ExecSyncResult yr = ExecBashSync(
        0,
        true,
        true,
        {},
        "echo '" + r.stdoutOutput + "' | yq -p=json -o=yaml");
    if (yr.exitCode != 0) {
        std::cerr << "Error: " << yr.stderrOutput << std::endl;
    }

    std::cout << yr.stdoutOutput << std::endl;
}

static int
ListModelsMain(int argc, const char** argv)
{
    if (argc > 1)
        return CLI_INVALID_ARGS;

    listModels();

    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_STORAGE,
    "list_models",
    ListModelsMain,
    NULL,
    "List external storage models.",
    "list_models");
