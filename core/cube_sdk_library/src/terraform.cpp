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
        // the output is captured and logged below rather than read on a terminal, so keep
        // terraform's ANSI colour escapes out of syslog
        "-no-color",
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
        true /*captureStdout*/,
        true /*captureStderr*/,
        {},
        std::string() + "/usr/local/bin/terraform-cube.sh " + argumentLine.str());
    if (r.exitCode == 0) {
        return true;
    }

    HexLogError(
        "terraform %s on module %s failed (exit %d)",
        command.c_str(),
        terraformModule.c_str(),
        r.exitCode);

    // terraform names the actual cause -- a provider error, a locked state, a missing
    // variable -- in its diagnostics and nowhere else. Left uncaptured those went to
    // hex_config's inherited stdio and never reached the log, so a failed module left only
    // the caller's own "failed to ..." line and had to be reproduced by hand to learn why.
    // Log it a line at a time: syslog truncates a single long message and terraform's error
    // blocks are long.
    std::stringstream diagnostics(r.stderrOutput.empty() ? r.stdoutOutput : r.stderrOutput);
    std::string line;
    while (std::getline(diagnostics, line)) {
        if (!line.empty()) {
            HexLogError("terraform: %s", line.c_str());
        }
    }

    return false;
}
