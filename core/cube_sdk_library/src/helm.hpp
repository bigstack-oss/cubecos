// CUBE SDK

#ifndef CUBE_HELM_H
#define CUBE_HELM_H

#include <hex/process_util.h>

#include <string>

/**
 * Execute a helm command on a release in a namespace.
 */
bool ExecHelm(
    const std::string command,
    const std::string releaseName,
    const std::string appNamespace);

#endif /* endif CUBE_HELM_H */
