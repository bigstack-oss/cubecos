// CUBE SDK

#ifndef CUBE_FILESYSTEM_H
#define CUBE_FILESYSTEM_H

#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <regex>
#include <sstream>
#include <string>
#include <unistd.h>

/**
 * Get all files under a directory.
 *
 * @param error error messages
 * @param path path of a directory
 * @return a list of files in full path
 */
const std::vector<std::string>
GetFilesUnderDirectory(
    std::string& error,
    const std::string& path);

/**
 * Check if any file under a directory matches the glob pattern.
 *
 * @param error The error message if the function return false.
 */
bool HasFileMatchGlob(
    std::string& error,
    const std::string& directory,
    const std::string& pattern);

/**
 * Read the file content into a string. Do not use it with a large file.
 */
const std::string
ReadFile(
    std::string& error,
    const std::string& fileName);

/**
 * Delete a file.
 *
 * @return true: Either the file does not exist or the deletion is successful.
 * false: Either the file is a directory or the deletion failed.
 */
bool DeleteFile(const std::string& fileName);

/**
 * Write contents to a file.
 *
 * The file permission would be 0644 if created.
 *
 * @param error error string to be returned
 * @param name file name
 * @param content file content
 * @return success or not
 */
bool WriteFile(
    std::string& error,
    const std::string& name,
    const std::vector<std::string>& content);

/**
 * The object type for temporary file operations
 */
struct TempFile {
    TempFile();

    bool isValid;
    int fd;
    std::string fileName;
};

/**
 * Create a temp file using mkstemp.
 */
const TempFile
CreateTempFile();

/**
 * Close the temp file's file descriptor
 */
void CloseTempFileFd(TempFile& tmpFile);

/**
 * Delete the temp file and close the file descriptor as well.
 *
 * After calling this function on the TempFile object, the object is not usable afterward.
 */
void DeleteTempFile(TempFile& tmpFile);

/**
 * Copy the file content from the source file path to the destination file descriptor.
 *
 * @param error The error message if the function return false.
 * @return true: The file content is copied. false: otherwise.
 */
bool CopyFile(
    std::string& error,
    const std::filesystem::path& srcPath,
    const std::filesystem::path& destPath);

#endif /* endif CUBE_FILESYSTEM_H */
