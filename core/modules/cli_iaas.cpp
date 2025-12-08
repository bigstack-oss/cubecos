// CUBE SDK

#include "cli_iaas.hpp"

// This mode is not available in STRICT error state
CLI_MODE(
    CLI_TOP_MODE,
    CLI_TOP_COMMAND_IAAS,
    "Work with IaaS settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

const std::vector<ExistingBackend>
GetExistingBackends()
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
    std::vector<ExistingBackend> backends;
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

const std::vector<IniSection>
GetConfiguredBackendDetails(const std::string& name)
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
