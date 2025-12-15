// CUBE SDK

#ifndef CUBE_YAML_H
#define CUBE_YAML_H

#include <hex/exec.hpp>
#include <string>

/**
 * Parse the YAML file into a JSON string.
 *
 * @param error
 * @param yamlFilePath
 * @return JSON string
 */
const std::string
YamlFileToJson(
    std::string& error,
    const std::string& yamlFilePath);

#endif /* endif CUBE_YAML_H */
