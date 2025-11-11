// CUBE SDK

#ifndef CUBE_TERRAFORM_H
#define CUBE_TERRAFORM_H

#include <hex/log.h>
#include <hex/process_util.h>

#include <sstream>
#include <string>
#include <vector>

/**
 * Execute a terraform command on a module.
 */
bool ExecTerraform(
    const std::string command,
    const std::string terraformModule,
    const std::vector<std::string> variables,
    const std::vector<std::string> variableFiles);

#endif /* endif CUBE_TERRAFORM_H */
