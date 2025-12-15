// CUBE SDK

#include "yaml.hpp"

const std::string
YamlFileToJson(
    std::string& error,
    const std::string& yamlFilePath)
{
    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        {},
        "/usr/local/bin/yq -p=yaml -o=json \"" + yamlFilePath + "\"");
    if (r.exitCode != 0) {
        error = r.stderrOutput;
        return "";
    }

    return r.stdoutOutput;
}

bool YamlFromJson(std::string& output, const std::string& input)
{
    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        {},
        "/usr/bin/echo '" + input + "' | /usr/local/bin/yq -p=json -o=yaml");
    if (r.exitCode != 0) {
        output = r.stderrOutput;
        return false;
    }

    output = r.stdoutOutput;
    return true;
}
