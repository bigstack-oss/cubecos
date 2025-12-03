// CUBE SDK

#include "openstack.hpp"

/**
 * Trim the leadning and ending spaces in a string.
 *
 * TODO: move this to string.hpp after the refactor branch is rebased.
 */
const std::string
trim(const std::string& str)
{
    // find the first non-whitespace character (start)
    const std::size_t first = str.find_first_not_of(" \t\n\r");
    if (std::string::npos == first) {
        // string is all whitespaces
        return "";
    }

    // find the last non-whitespace character (end)
    const std::size_t last = str.find_last_not_of(" \t\n\r");

    // extract the substring between start and end
    return str.substr(first, (last - first + 1));
}

/**
 * Remove the matching prefix.
 *
 * TODO: move this to string.hpp after the refactor branch is rebased.
 */
std::string removePrefix(const std::string& line, const std::string& prefix)
{
    // check if the line starts with the prefix, the prefix must be found at position 0
    if (line.rfind(prefix, 0) == 0) {
        // if it is found, return the substring starting immediately after the prefix length
        return line.substr(prefix.length());
    }

    // if the prefix is not found, return the original string unchanged.
    return line;
}

/**
 * Parse an INI config.
 */
const std::map<std::string, std::string>
parseIni(const std::vector<std::string>& configLines)
{
    std::map<std::string, std::string> settings;

    for (const std::string& line : configLines) {
        std::string key;
        std::string value;

        std::size_t equalPosition = line.find('=');

        if (equalPosition == std::string::npos) {
            // not found
            key = trim(line);
            value = "";
        } else {
            key = trim(line.substr(0, equalPosition));
            value = trim(line.substr(equalPosition + 1));
        }

        settings.emplace(key, value);
    }

    return settings;
}

const std::map<std::string, std::string>
parseOpenstackCliAuth()
{
    // read the openrc file
    std::string fsError;
    const std::string openstackCliAuthString = ReadFile(fsError, OPENSTACK_CLI_AUTH);

    std::stringstream ss(openstackCliAuthString);
    std::string line;
    std::vector<std::string> configLines;
    while (std::getline(ss, line)) {
        configLines.push_back(removePrefix(trim(line), "export "));
    }

    return parseIni(configLines);
}

const ExecSyncResult
OpenstackExec(const std::vector<std::string>& args)
{
    std::stringstream argumentLine;
    bool isFirst = true;
    for (const std::string& a : args) {
        if (isFirst) {
            argumentLine << a;
            isFirst = false;
        } else {
            argumentLine << " " << a;
        }
    }
    HexLogInfo("execute openstack cli: %s", argumentLine.str().c_str());

    Cmd c;
    c.path = OPENSTACK_CLI;
    c.args = args;
    c.captureStdout = true;
    c.captureStderr = true;

    // set openstack admin rc for openstack cli auth
    const std::map<std::string, std::string> openstackCliAuth = parseOpenstackCliAuth();
    c.env = openstackCliAuth;

    const ExecSyncResult r = ExecSync(0, c);
    if (r.isTimedOut) {
        HexLogInfo("openstack cli timedout");
    }
    if (r.exitCode != 0) {
        HexLogInfo("openstack cli returned error");
    }

    HexLogInfo("executed openstack cli: %s", argumentLine.str().c_str());
    return r;
}
