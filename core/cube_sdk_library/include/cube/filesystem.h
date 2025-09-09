// CUBE SDK

#ifndef CUBE_FILESYSTEM_H
#define CUBE_FILESYSTEM_H

#ifdef __cplusplus

#include <filesystem>
#include <regex>
#include <sstream>
#include <string>

/**
 * Check if any glob pattern matched file name exists under a directory.
 */
bool FileExistsWithGlob(
    const std::string& directory,
    const std::string& pattern,
    std::string& error);

#endif // __cplusplus

#endif /* endif CUBE_NETWORK_H */
