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

/**
 * Parse the JSON string into an YAML string.
 *
 * @param output
 * @param input
 * @return parsing is successful or not
 */
bool YamlFromJson(std::string& output, const std::string& input);

#endif /* endif CUBE_YAML_H */
