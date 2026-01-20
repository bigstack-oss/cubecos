// CUBE SDK

#ifndef CUBE_SYSTEMD_UTIL_H
#define CUBE_SYSTEMD_UTIL_H

// Process extended API requires C++
#ifdef __cplusplus

#include <hex/exec.hpp>
#include <hex/log.h>
#include <hex/process_util.h>

bool SystemdCommitService(const bool enabled, const char* name, const bool retry, const bool quiet);

bool SystemdCommitService(const bool enabled, const char* name, const bool retry = false);

#endif // __cplusplus

#endif /* endif CUBE_SYSTEMD_UTIL_H */
