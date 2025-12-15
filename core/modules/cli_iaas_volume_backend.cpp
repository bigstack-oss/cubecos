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

static bool
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
        return false;
    }

    const ExecSyncResult yr = ExecBashSync(
        0,
        true,
        true,
        {},
        "/usr/bin/echo '" + r.stdoutOutput + "' | /usr/local/bin/yq -p=json -o=yaml");
    if (yr.exitCode != 0) {
        std::cerr << "Error: " << yr.stderrOutput << std::endl;
        return false;
    }

    std::cout << yr.stdoutOutput << std::endl;
    return true;
}

static int
ListModelsMain(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    if (!listModels()) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_STORAGE,
    "list_models",
    ListModelsMain,
    NULL,
    "List external storage models.",
    "list_models");

static const std::vector<std::string>
getDrivers(std::string& error)
{
    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        {},
        HEX_SDK " cinder_get_models");
    if (r.exitCode != 0) {
        std::cerr << "Error: " << r.stderrOutput << std::endl;
        error = "hex_sdk interface error";
        return {};
    }

    // parse the field driver
    std::string jsonError;
    const json11::Json modelList = json11::Json::parse(r.stdoutOutput, jsonError);
    if (!jsonError.empty()) {
        std::cerr << "Error: " << r.stderrOutput << std::endl;
        error = "json parsing error";
        return {};
    }

    std::vector<std::string> drivers;
    const json11::Json::array& models = modelList.array_items();
    for (const json11::Json& m : models) {
        if (!m["driver"].is_string()) {
            continue;
        }

        drivers.push_back(m["driver"].string_value());
    }

    return drivers;
}

static bool
listDrivers()
{
    std::string error;
    const std::vector<std::string> drivers = getDrivers(error);
    if (!error.empty()) {
        return false;
    }

    // print the drivers
    std::cout << "[Driver]" << std::endl;
    for (const std::string& d : drivers) {
        std::cout << "- " << d << std::endl;
    }
    return true;
}

static int
ListDriversMain(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    if (!listDrivers()) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_STORAGE,
    "list_drivers",
    ListDriversMain,
    NULL,
    "List external storage drivers in models.",
    "list_drivers");

static bool
listModel(const std::string& driver)
{
    // structure the payload
    json11::Json payload = json11::Json::object {
        { "driver", driver },
    };

    // call the hex_sdk interface
    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        {},
        HEX_SDK " cinder_get_model '" + payload.dump() + "'");
    if (r.exitCode != 0) {
        std::cerr << "Error: " << r.stderrOutput << std::endl;
        return false;
    }

    const ExecSyncResult yr = ExecBashSync(
        0,
        true,
        true,
        {},
        "/usr/bin/echo '" + r.stdoutOutput + "' | /usr/local/bin/yq -p=json -o=yaml");
    if (yr.exitCode != 0) {
        std::cerr << "Error: " << yr.stderrOutput << std::endl;
        return false;
    }

    std::cout << yr.stdoutOutput << std::endl;
    return true;
}

static int
ListModelMain(int argc, const char** argv)
{
    /**
     * [0] list_model
     * [1] <driver>
     */
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    std::string driver;

    // [1] <driver>
    if (!CliReadInputStr(
            argc,
            argv,
            1,
            "Enter the driver: ",
            &driver)) {
        std::cerr << "Field driver is required" << std::endl;
        return CLI_INVALID_ARGS;
    }

    if (!listModel(driver)) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_STORAGE,
    "list_model",
    ListModelMain,
    NULL,
    "List an external storage model by driver.",
    "list_model <driver>");

/**
 * Prepare the model file with console inputs.
 *
 * @param error
 * @param modelContent
 * @return the model file
 */
static TempFile
prepareModelFile(
    std::string& error,
    const std::string& modelContent)
{
    if (modelContent.empty()) {
        error = "model content should not be blank";
        return TempFile();
    }

    // pour the multiline input to a file
    TempFile f = CreateTempFile();

    FILE* fout = fdopen(f.fd, "w");
    if (!fout) {
        error = "failed to create a file to contain the model content";
        return f;
    }

    fprintf(fout, "%s", modelContent.c_str());
    fclose(fout);

    CloseTempFileFd(f);
    return f;
}

/**
 * Parse the model file into a JSON string.
 *
 * @param error
 * @param modelFilePath
 * @return model
 */
static const std::string
parseModel(
    std::string& error,
    const std::string& modelFilePath)
{
    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        {},
        "/usr/local/bin/yq -p=yaml -o=json \"" + modelFilePath + "\"");
    if (r.exitCode != 0) {
        error = r.stderrOutput;
        return "";
    }

    return r.stdoutOutput;
}

static bool
setModel(
    std::string& output,
    const std::string& model)
{
    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        {},
        HEX_SDK " cinder_put_model '" + model + "'");
    if (r.exitCode != 0) {
        output = r.stderrOutput;
        return false;
    }

    output = r.stdoutOutput;
    return true;
}

/**
 * Get the message field out of the output.
 *
 * @param output
 * @return message field string
 */
static const std::string
getMessage(const std::string& output)
{
    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        {},
        "/usr/bin/echo '" + output + "' | /usr/bin/jq -r \".message\"");
    if (r.exitCode != 0) {
        return r.stderrOutput;
    }

    return r.stdoutOutput;
}

static int
SetModelMain(int argc, const char** argv)
{
    /**
     * [0] set_model
     * [1] <local | console>
     * [2] <local_model_file_name | model_content>
     */
    if (argc > 3) {
        return CLI_INVALID_ARGS;
    }

    const std::string localDirectory = "/var/update";

    // collect inputs
    int index;
    std::string sourceType;
    std::string modelFilePath;
    std::string modelContent;

    CliList sourceTypes;
    sourceTypes.push_back("local");
    sourceTypes.push_back("console");

    // [1] <local | console>
    if (CliMatchListHelper(
            argc,
            argv,
            1,
            sourceTypes,
            &index,
            &sourceType,
            "Select input method: ")
        != 0) {
        std::cerr << "Input method is missing or invalid" << std::endl;
        return CLI_INVALID_ARGS;
    }

    if (sourceType == "local") {
        // [2] <local_model_file_name>
        const std::string message = "Please prepare the model file under "
            + localDirectory
            + " . Select the input file: ";
        std::cout << "" << localDirectory << std::endl;
        if (CliMatchCmdHelper(
                argc,
                argv,
                2,
                "find " + localDirectory + "/ -type f -print0 | xargs -0 -n 1 basename",
                &index,
                &modelFilePath,
                message.c_str())
            != 0) {
            std::cerr << "File " << modelFilePath << " not found" << std::endl;
            return CLI_INVALID_ARGS;
        }
    } else {
        // [2] <model_content>
        if (!CliReadMultipleLines("Please enter the content of the model: ", modelContent)) {
            std::cerr << "Invalid file content" << std::endl;
            return CLI_INVALID_ARGS;
        }
    }

    // parse the model
    std::string model;
    if (sourceType == "local") {
        std::string error;

        model = parseModel(
            error,
            std::filesystem::path(localDirectory) / std::filesystem::path(modelFilePath));
        if (!error.empty()) {
            std::cerr << "Error: " << error << std::endl;
            return CLI_FAILURE;
        }
    } else if (sourceType == "console") {
        // prepare the model file
        std::string error;

        TempFile f = prepareModelFile(error, modelContent);
        if (!error.empty()) {
            std::cerr << "Error: " << error << std::endl;
            DeleteTempFile(f);
            return CLI_FAILURE;
        }

        model = parseModel(error, f.fileName);
        if (!error.empty()) {
            std::cerr << "Error: " << error << std::endl;
            DeleteTempFile(f);
            return CLI_FAILURE;
        }

        DeleteTempFile(f);
    }

    // set the model
    std::string output;
    if (!setModel(output, model)) {
        std::cerr << "Error: " << getMessage(output) << std::endl;
        return CLI_FAILURE;
    }

    std::cout << getMessage(output) << std::endl;
    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_STORAGE,
    "set_model",
    SetModelMain,
    NULL,
    "Set an external storage model.",
    "set_model <local | console> <local_model_file_name | model_content>");

static bool
deleteModel(
    std::string& output,
    const std::string& driver)
{
    // structure the payload
    json11::Json payload = json11::Json::object {
        { "driver", driver },
    };

    // call the hex_sdk interface
    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        {},
        HEX_SDK " cinder_delete_model '" + payload.dump() + "'");
    if (r.exitCode != 0) {
        output = r.stderrOutput;
        return false;
    }

    output = r.stdoutOutput;
    return true;
}

static int
DeleteModelMain(int argc, const char** argv)
{
    /**
     * [0] delete_model
     * [1] <driver>
     */
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    std::string driver;

    // [1] <driver>
    if (!CliReadInputStr(
            argc,
            argv,
            1,
            "Enter the driver: ",
            &driver)) {
        std::cerr << "Field driver is required" << std::endl;
        return CLI_INVALID_ARGS;
    }

    std::string output;
    if (!deleteModel(output, driver)) {
        std::cerr << "Error: " << output << std::endl;
        return CLI_FAILURE;
    }

    std::cout << getMessage(output) << std::endl;
    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_STORAGE,
    "delete_model",
    DeleteModelMain,
    NULL,
    "Delete an external storage model.",
    "delete_model <driver>");

/**
 * Get the active multipath settings in the kernel.
 *
 * @param output
 * @return active multipath settings in YAML
 */
static bool
getActiveMultipathSetting(std::string& output)
{
    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        {},
        HEX_SDK " cinder_get_active_multipath_setting");
    if (r.exitCode != 0) {
        output = r.stderrOutput;
        return false;
    }

    const ExecSyncResult yr = ExecBashSync(
        0,
        true,
        true,
        {},
        "echo '" + r.stdoutOutput + "' | /usr/local/bin/yq -p=json -o=yaml");
    if (yr.exitCode != 0) {
        output = yr.stderrOutput;
        return false;
    }

    output = yr.stdoutOutput;
    return true;
}

static int
GetActiveMultipathSettingMain(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    std::string output;
    if (!getActiveMultipathSetting(output)) {
        std::cerr << "Error: " << output << std::endl;
        return CLI_FAILURE;
    }

    std::cout << output << std::endl;
    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_STORAGE,
    "get_active_multipath_setting",
    GetActiveMultipathSettingMain,
    NULL,
    "Get the active multipath settings.",
    "get_active_multipath_setting");
