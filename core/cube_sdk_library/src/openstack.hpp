// CUBE SDK

#ifndef CUBE_OPENSTACK_H
#define CUBE_OPENSTACK_H

#include <constant.hpp>
#include <filesystem.hpp>
#include <hex/exec.hpp>
#include <hex/log.h>
#include <sstream>

#define OPENSTACK_CLI_AUTH "/etc/admin-openrc.sh"

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
 * Execute OpenStack CLI.
 */
const ExecSyncResult
OpenstackExec(const std::string& command);

#endif /* endif CUBE_OPENSTACK_H */
