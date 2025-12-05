// CUBE SDK

#include "cli_iaas_volume_backend.hpp"

// This mode is not available in STRICT error state
CLI_MODE(
    CLI_TOP_COMMAND_IAAS,
    CLI_COMMAND_IAAS_STORAGE,
    "Work with external settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

struct existingBackend {
    std::string host;
    std::string zone;
    std::string status;
    std::string state;
    std::string updatedAt;
};

static const std::vector<existingBackend>
getExistingBackends()
{
    const ExecSyncResult r = OpenstackExec("volume service list -f json");
    if (r.exitCode != 0) {
        HexLogError("failed to get openstack cinder volume service list, %s", r.stderrOutput.c_str());
        return {};
    }

    // parse the volume service list
    std::string jsonError;
    const json11::Json volumeServiceList = json11::Json::parse(r.stdoutOutput, jsonError);
    if (!jsonError.empty()) {
        HexLogError("failed to parse openstack cinder volume service list, %s", jsonError.c_str());
        return {};
    }

    // perform the filtering
    const json11::Json::array& volumeServices = volumeServiceList.array_items();
    std::vector<existingBackend> backends;
    for (const json11::Json& s : volumeServices) {
        if (!s["Binary"].is_string()) {
            continue;
        }

        if (s["Binary"].string_value() != "cinder-volume") {
            continue;
        }

        std::string host = s["Host"].is_string() ? s["Host"].string_value() : "";
        std::string zone = s["Zone"].is_string() ? s["Zone"].string_value() : "";
        std::string status = s["Status"].is_string() ? s["Status"].string_value() : "";
        std::string state = s["State"].is_string() ? s["State"].string_value() : "";
        std::string updatedAt = s["Updated At"].is_string() ? s["Updated At"].string_value() : "";

        backends.push_back({
            .host = host,
            .zone = zone,
            .status = status,
            .state = state,
            .updatedAt = updatedAt,
        });
    }

    return backends;
}

static void
listExistingBackends()
{
    const std::vector<existingBackend> backends = getExistingBackends();

    // output to the terminal
    std::cout << "[Current Cinder Volume Backends]" << std::endl;
    for (const existingBackend& b : backends) {
        std::cout << "  Host: " << b.host << std::endl;
        std::cout << "  Zone: " << b.zone << std::endl;
        std::cout << "  Status: " << b.status << std::endl;
        std::cout << "  State: " << b.state << std::endl;
        std::cout << "  Updated At: " << b.updatedAt << std::endl;
        std::cout << std::endl;
    }
}

const std::vector<IniSection>
getConfiguredBackendDetails(const std::string& name)
{
    // read the backend config file
    std::string configFilePath = std::string(CINDER_BACKEND_DIR) + "/ext_storage_" + name + ".conf";
    std::string fsError;
    const std::string backendConfig = ReadFile(fsError, configFilePath);
    if (!fsError.empty()) {
        HexLogError("failed to read the backend config file, %s", fsError.c_str());
        return {};
    }

    return ParseIni(backendConfig);
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

        const std::vector<IniSection> backendConfig = getConfiguredBackendDetails(b);
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
