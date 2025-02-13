// CUBE SDK

#ifndef CUBE_CONFIG_H
#define CUBE_CONFIG_H

// Process extended API requires C++
#ifdef __cplusplus

#include <map>

// pick one never seen in configuration files
#define GLOBAL_SEC "{[(^)]}"

// format for parsing section name, should comply with sscanf format
#define SB_SEC_RFMT "[%[^]]"  // square bracket section format. e.g. [section]

// format for writing section name, should comply with snprintf format
#define SB_SEC_WFMT "[%s]"


typedef std::map<std::string, std::string> ConfigList;
typedef std::map<std::string, ConfigList> Configs;

bool LoadConfig(const char* filepath, const char* secfmt, const char sep, Configs& config);
bool WriteConfig(const char* filepath, const char* secfmt, const char sep, Configs& config);
bool DumpConfig(const char* secfmt, const char delimiter, Configs& config);

#endif // __cplusplus

#endif /* endif CUBE_CONFIG_H */

