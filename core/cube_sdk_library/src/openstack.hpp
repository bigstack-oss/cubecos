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
 * Execute OpenStack CLI.
 */
const ExecSyncResult
OpenstackExec(const std::string& command);

#endif /* endif CUBE_OPENSTACK_H */
