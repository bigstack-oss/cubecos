// CUBE SDK

#include "cli_management_cleanup.hpp"

// This mode is not available in STRICT error state
CLI_MODE(
    "management",
    "cleanup",
    "Work with remnants cleanup after upgrade.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

static bool
cleanupSenlinEndpoints(std::string& error)
{
    const ExecSyncResult r = OpenstackExec("endpoint list -f json");
    if (r.exitCode != 0) {
        error = "failed to get OpenStack endpoint list";
        HexLogError("%s", error.c_str());
        return false;
    }

    std::string jsonError;
    const json11::Json serviceList = json11::Json::parse(r.stdoutOutput, jsonError);
    if (!jsonError.empty()) {
        error = "json parsing error, error: " + r.stderrOutput;
        HexLogError("%s", error.c_str());
        return false;
    }

    std::vector<std::string> endpointIds;
    const json11::Json::array& services = serviceList.array_items();
    for (const json11::Json& s : services) {
        if (!s["Service Name"].is_string()) {
            continue;
        }

        if (s["Service Name"].string_value() != "senlin") {
            continue;
        }

        if (!s["ID"].is_string()) {
            continue;
        }

        endpointIds.push_back(s["ID"].string_value());
    }

    if (endpointIds.empty()) {
        // no endpoint to delete
        return true;
    }

    std::stringstream endpoints;
    for (const std::string& e : endpointIds) {
        endpoints << " " << e;
    }

    const ExecSyncResult dr = OpenstackExec("endpoint delete" + endpoints.str());
    if (dr.exitCode != 0) {
        error = "failed to delete OpenStack Senlin endpoints";
        HexLogError("%s", error.c_str());
        return false;
    }

    return true;
}

static bool
cleanupSenlinService(std::string& error)
{
    // first, check if the service exists
    const ExecSyncResult r = OpenstackExec("service show senlin");
    if (r.exitCode != 0) {
        // the service is already deleted
        return true;
    }

    const ExecSyncResult dr = OpenstackExec("service delete senlin");
    if (dr.exitCode != 0) {
        error = "failed to delete OpenStack Senlin service";
        HexLogError("%s", error.c_str());
        return false;
    }

    return true;
}

static const char BOOT_SETTINGS[] = "/etc/settings.txt";

static bool
deleteSenlinUser(std::string& error)
{
    // first, get the domain of OpenStack
    const std::string cubecosBootConfig = ReadFile(error, BOOT_SETTINGS);
    if (!error.empty()) {
        HexLogError("%s", error.c_str());
        return false;
    }

    std::string domain;

    const std::vector<IniSection> settings = ParseIni(cubecosBootConfig);
    for (const IniSection& i : settings) {
        if (i.header != "") {
            continue;
        }

        if (i.settings.count("cubesys.domain") == 0) {
            continue;
        }

        domain = i.settings.at("cubesys.domain");
    }

    if (domain.empty()) {
        error = "failed to get the OpenStack domain";
        HexLogError("%s", error.c_str());
        return false;
    }

    // check if the user exists
    const ExecSyncResult r = OpenstackExec("user show --domain " + domain + " senlin");
    if (r.exitCode != 0) {
        // the user is already deleted
        return true;
    }

    // delete the user
    const ExecSyncResult dr = OpenstackExec("user delete --domain " + domain + " senlin");
    if (dr.exitCode != 0) {
        error = "failed to delete the OpenStack Senlin user";
        HexLogError("%s", error.c_str());
        return false;
    }

    return true;
}

static int
CleanupSenlinMain(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    std::string error;
    if (!cleanupSenlinEndpoints(error)) {
        std::cerr << "Error: failed to clean up Senlin endpoints" << std::endl;
        std::cerr << "Error: " << error << std::endl;
        return CLI_FAILURE;
    } else {
        std::cout << "OpenStack Senlin endpoints deleted." << std::endl;
    }

    if (!cleanupSenlinService(error)) {
        std::cerr << "Error: " << error << std::endl;
        return CLI_FAILURE;
    } else {
        std::cout << "OpenStack Senlin service deleted." << std::endl;
    }

    if (!deleteSenlinUser(error)) {
        std::cerr << "Error: " << error << std::endl;
        return CLI_FAILURE;
    } else {
        std::cout << "OpenStack Senlin user deleted." << std::endl;
    }

    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    "cleanup",
    "cleanup_senlin",
    CleanupSenlinMain,
    NULL,
    "Clean up OpenStack Senlin remnants after upgrade.",
    "reset [<volume id>]");
