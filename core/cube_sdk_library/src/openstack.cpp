// CUBE SDK

#include "openstack.hpp"

const std::string
Trim(const std::string& str)
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
const std::string
RemovePrefix(const std::string& line, const std::string& prefix)
{
    // check if the line starts with the prefix, the prefix must be found at position 0
    if (line.rfind(prefix, 0) == 0) {
        // if it is found, return the substring starting immediately after the prefix length
        return line.substr(prefix.length());
    }

    // if the prefix is not found, return the original string unchanged.
    return line;
}

const std::map<std::string, std::string>
ParseEnv(const std::vector<std::string>& configLines)
{
    std::map<std::string, std::string> settings;

    for (const std::string& line : configLines) {
        std::string key;
        std::string value;

        std::size_t equalPosition = line.find('=');

        if (equalPosition == std::string::npos) {
            // not found
            key = Trim(line);
            value = "";
        } else {
            key = Trim(line.substr(0, equalPosition));
            value = Trim(line.substr(equalPosition + 1));
        }

        if (key.empty()) {
            continue;
        }

        settings.emplace(key, value);
    }

    return settings;
}

const std::vector<IniSection>
ParseIni(const std::string& config)
{
    // group ini config into sections
    std::map<std::string, std::vector<std::string>> sections;
    std::stringstream ss(config);
    std::string line;
    std::string header = "";
    while (std::getline(ss, line)) {
        const std::string trimmedLine = Trim(line);

        if (trimmedLine.empty()) {
            continue;
        }

        // detect the header
        if (trimmedLine.length() >= 2) {
            if (trimmedLine.front() == '[' && trimmedLine.back() == ']') {
                header = trimmedLine.substr(1, trimmedLine.length() - 2);
                continue;
            }
        }

        // if not a header, push the line into the section
        if (sections.count(header) == 0) {
            sections.emplace(header, std::vector<std::string>());
        }
        sections[header].push_back(line);
    }

    // form the output
    std::vector<IniSection> result;
    for (const std::pair<std::string, std::vector<std::string>> s : sections) {
        // parse the section header
        IniSection i = {
            .header = s.first,
        };

        // parse settings
        i.settings = ParseEnv(s.second);

        result.push_back(i);
    }
    return result;
}

const std::map<std::string, std::string>
ParseOpenstackCliAuth()
{
    // read the openrc file
    std::string fsError;
    const std::string openstackCliAuthString = ReadFile(fsError, OPENSTACK_CLI_AUTH);
    if (!fsError.empty()) {
        HexLogError("failed to read admin openrc for openstack cli, %s", fsError.c_str());
        return {};
    }

    std::stringstream ss(openstackCliAuthString);
    std::string line;
    std::vector<std::string> configLines;
    while (std::getline(ss, line)) {
        configLines.push_back(RemovePrefix(Trim(line), "export "));
    }

    return ParseEnv(configLines);
}

const ExecSyncResult
OpenstackExec(const std::string& command)
{
    HexLogInfo("execute openstack cli: %s", command.c_str());

    std::string openstackCommand = std::string(OPENSTACK_CLI) + std::string(" ") + command;

    // set openstack admin rc for openstack cli auth
    const std::map<std::string, std::string> openstackCliAuth = ParseOpenstackCliAuth();

    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        openstackCliAuth,
        openstackCommand);

    if (r.isTimedOut) {
        HexLogInfo("openstack cli timedout");
    }
    if (r.exitCode != 0) {
        HexLogInfo("openstack cli returned error");
    }

    HexLogInfo("executed openstack cli: %s", command.c_str());
    return r;
}

const std::string
GetProjectId(const std::string& domain, const std::string& project)
{
    const ExecSyncResult r = OpenstackExec(
        "project show --domain \"" + domain
        + "\" \"" + project + "\" -f json");
    if (r.exitCode != 0) {
        return "";
    }

    // parse the output
    std::string jsonError;
    const json11::Json projectDetail = json11::Json::parse(r.stdoutOutput, jsonError);
    if (!jsonError.empty()) {
        HexLogError("%s", jsonError.c_str());
        return "";
    }
    if (!projectDetail["id"].is_string()) {
        return "";
    }

    return projectDetail["id"].string_value();
}

const QuotaWithUsage
GetQuotaWithUsage(
    std::string& error,
    const std::string& domain,
    const std::string& project,
    const QuotaResourceType& resourceType,
    const std::string& resource)
{
    const std::string projectId = GetProjectId(domain, project);
    if (projectId.empty()) {
        error = "failed to get the project id";
        return {};
    }

    std::string resourceTypeFlag;
    switch (resourceType) {
    case QuotaResourceType::all:
        resourceTypeFlag = "--all";
        break;
    case QuotaResourceType::compute:
        resourceTypeFlag = "--compute";
        break;
    case QuotaResourceType::volume:
        resourceTypeFlag = "--volume";
        break;
    case QuotaResourceType::network:
        resourceTypeFlag = "--network";
        break;
    default:
        error = "the resource type is not supported";
        return {};
    }

    const ExecSyncResult r = OpenstackExec(
        "quota show " + resourceTypeFlag + " --usage \"" + projectId
        + "\" -f json");
    if (r.exitCode != 0) {
        error = "failed to get the quota details";
        return {};
    }

    // parse the output
    std::string jsonError;
    const json11::Json quotaList = json11::Json::parse(r.stdoutOutput, jsonError);
    if (!jsonError.empty()) {
        error = jsonError;
        return {};
    }

    int limit = 0;
    int used = 0;
    int reserved = 0;
    const json11::Json::array& quotas = quotaList.array_items();
    for (const json11::Json& q : quotas) {
        if (!q["Resource"].is_string()) {
            continue;
        }

        if (q["Resource"].string_value() != resource) {
            continue;
        }

        if (!q["Limit"].is_number()) {
            error = "failed to parse the limit of resource " + resource;
            return {};
        }
        limit = q["Limit"].number_value();

        if (!q["In Use"].is_number()) {
            error = "failed to parse the in use of resource " + resource;
            return {};
        }
        used = q["In Use"].number_value();

        if (!q["Reserved"].is_number()) {
            error = "failed to parse the reserved of resource " + resource;
            return {};
        }
        reserved = q["Reserved"].number_value();

        break;
    }

    return {
        .limit = limit,
        .used = used,
        .reserved = reserved,
    };
}

const bool
IsQuotaGigabytesEnough(
    const std::string& domain,
    const std::string& project,
    const long long& needSpaceInBytes)
{
    std::string error;
    const QuotaWithUsage q = GetQuotaWithUsage(
        error,
        domain,
        project,
        QuotaResourceType::volume,
        "gigabytes");

    if (!error.empty()) {
        HexLogError("%s", error.c_str());
        return false;
    }

    if (q.limit == -1) {
        // we have no limit here
        return true;
    }

    long long freeSize = q.limit - q.used;
    return (needSpaceInBytes <= (freeSize << 10 << 10 << 10));
}

const bool
IsQuotaVolumesEnough(
    const std::string& domain,
    const std::string& project)
{
    std::string error;
    const QuotaWithUsage q = GetQuotaWithUsage(
        error,
        domain,
        project,
        QuotaResourceType::volume,
        "volumes");

    if (!error.empty()) {
        HexLogError("%s", error.c_str());
        return false;
    }

    if (q.limit == -1) {
        // we have no limit here
        return true;
    }

    return (q.used < q.limit);
}
