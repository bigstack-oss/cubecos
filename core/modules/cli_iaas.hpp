// CUBE SDK

#ifndef CLI_IAAS_H
#define CLI_IAAS_H

#include <constant.hpp>
#include <cube/cubesys.h>
#include <hex/cli_module.h>
#include <hex/cli_util.h>
#include <hex/strict.h>
#include <openstack.hpp>
#include <third_party/json11.hpp>

#define CLI_TOP_COMMAND_IAAS "iaas"

#define CINDER_VOLUME_DRIVER_NFS "cinder.volume.drivers.nfs.NfsDriver"

struct ExistingBackend {
    std::string host;
    std::string zone;
    std::string status;
    std::string state;
    std::string updatedAt;
};

/**
 * Get existing backends from OpenStack.
 */
const std::vector<ExistingBackend>
GetExistingBackends();

/**
 * Get configured backend details by name.
 */
const std::vector<IniSection> GetConfiguredBackendDetails(const std::string& name);

#endif /* endif CLI_IAAS_H */
