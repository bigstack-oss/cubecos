// CUBE SDK

#include "terraform.hpp"

bool ExecTerraform(
    const std::string command,
    const std::string terraformModule,
    const std::vector<std::string> variables,
    const std::vector<std::string> variableFiles)
{
    std::vector<std::string> arguments = {
        command,
        "-auto-approve",
        "-target=module." + terraformModule,
    };

    if (command.compare("destroy") == 0) {
        arguments.push_back("-refresh=false");
    }

    for (const std::string& v : variables) {
        arguments.push_back("-var");
        arguments.push_back(v);
    }

    for (const std::string& vf : variableFiles) {
        arguments.push_back("-var-file=" + vf);
    }

    std::stringstream argumentLine;
    bool isFirst = true;
    for (const std::string& a : arguments) {
        if (isFirst) {
            argumentLine << a;
            isFirst = false;
        } else {
            argumentLine << " " << a;
        }
    }

    HexLogInfo(
        "terraform apply command: %s, module: %s, full line: %s",
        command.c_str(),
        terraformModule.c_str(),
        argumentLine.str().c_str());

    const ExecSyncResult r = ExecBashSync(
        0,
        false,
        false,
        {},
        std::string() + "/usr/local/bin/terraform-cube.sh " + argumentLine.str());
    return (r.exitCode == 0);
}
