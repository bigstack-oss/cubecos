// CUBE SDK

#include <cube/filesystem.h>

bool FileExistsWithGlob(
    const std::string& directory,
    const std::string& pattern,
    std::string& error)
{
    std::filesystem::path dirPath(directory);

    // Create a regex from the glob pattern
    // Replace '*' with '.*' for regex matching and escape other special characters
    std::string regexPattern = "^" + pattern + "$";
    regexPattern = std::regex_replace(regexPattern, std::regex("\\."), "\\.");
    regexPattern = std::regex_replace(regexPattern, std::regex("\\*"), ".*");

    std::regex fileRegex(regexPattern);

    try {
        if (!std::filesystem::exists(dirPath) || !std::filesystem::is_directory(dirPath)) {
            return false;
        }

        for (const std::filesystem::directory_entry& entry : std::filesystem::directory_iterator(dirPath)) {
            if (std::filesystem::is_regular_file(entry.path())) {
                std::string filename = entry.path().filename().string();
                if (std::regex_match(filename, fileRegex)) {
                    return true;
                }
            }
        }
    } catch (const std::filesystem::filesystem_error& e) {
        std::stringstream errorOutput;
        errorOutput << "Filesystem error: " << e.what();
        error = errorOutput.str();
        return false;
    }

    return false;
}
