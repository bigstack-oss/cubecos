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
