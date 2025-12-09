// CUBE SDK

#ifndef CUBE_OPENSTACK_H
#define CUBE_OPENSTACK_H

#include "third_party/json11.hpp"
#include <constant.hpp>
#include <filesystem.hpp>
#include <hex/exec.hpp>
#include <hex/log.h>
#include <sstream>

#define OPENSTACK_CLI_AUTH "/etc/admin-openrc.sh"

/**
 * Trim the leadning and ending spaces in a string.
 *
 * TODO: move this to string.hpp after the refactor branch is rebased.
 */
const std::string
Trim(const std::string& str);

/**
 * Remove the matching prefix.
 *
 * TODO: move this to string.hpp after the refactor branch is rebased.
 */
const std::string
RemovePrefix(const std::string& line, const std::string& prefix);

/**
 * Parse an env file.
 */
const std::map<std::string, std::string>
ParseEnv(const std::vector<std::string>& configLines);

/**
 * Ini section structure.
 */
struct IniSection {
    std::string header;
    std::map<std::string, std::string> settings;
};

/**
 * Parse an ini file.
 */
const std::vector<IniSection>
ParseIni(const std::string& config);

/**
 * Parse OpenStack admin-openrc into the env format.
 */
const std::map<std::string, std::string>
ParseOpenstackCliAuth();

/**
 * Execute OpenStack CLI.
 */
const ExecSyncResult
OpenstackExec(const std::string& command);

/**
 * Get the project ID by the domain and the project name.
 *
 * @param domain
 * @param project
 * @return project ID, if failed, blank
 */
const std::string
GetProjectId(const std::string& domain, const std::string& project);

struct QuotaWithUsage {
    int limit;
    int used;
    int reserved;
};

enum QuotaResourceType {
    all,
    compute,
    volume,
    network,
};

/**
 * Get the quota with usage.
 *
 * @param error error messages
 * @param domain
 * @param project
 * @param resourceType
 * @param resource
 * @return quota with usage
 */
const QuotaWithUsage
GetQuotaWithUsage(
    std::string& error,
    const std::string& domain,
    const std::string& project,
    const QuotaResourceType& resourceType,
    const std::string& resource);

/**
 * Check if the quota gigabytes of the project enough to contain the volume.
 *
 * @param domain
 * @param project
 * @param needSpaceInBytes
 * @return is quota enough or not
 */
const bool
IsQuotaGigabytesEnough(
    const std::string& domain,
    const std::string& project,
    const long long& needSpaceInBytes);

/**
 * Check if the quota volumes of the project is still available.
 *
 * @param domain
 * @param project
 * @return is quota enough or not
 */
const bool
IsQuotaVolumesEnough(
    const std::string& domain,
    const std::string& project);

/**
 * Get the volume type by ID.
 *
 * @param volumeId
 * @return volume type
 */
const std::string
GetVolumeTypeById(const std::string& volumeId);

#endif /* endif CUBE_OPENSTACK_H */
