// CUBE SDK

#include "filesystem.hpp"

bool HasFileMatchGlob(
    std::string& error,
    const std::string& directory,
    const std::string& pattern)
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

const std::string
ReadFile(
    std::string& error,
    const std::string& fileName)
{
    std::ifstream file(fileName);
    if (!file.is_open()) {
        error = "failed to open the file";
        return "";
    }

    std::stringstream output;
    output << file.rdbuf();
    return output.str();
}

bool DeleteFile(const std::string& fileName)
{
    if (!std::filesystem::exists(fileName)) {
        return true;
    }

    if (std::filesystem::is_directory(fileName)) {
        return false;
    }

    return unlink(fileName.c_str()) == 0;
}

TempFile::TempFile()
    : isValid(false)
    , fd(-1)
    , fileName("")
{
}

const TempFile
CreateTempFile()
{
    TempFile result = TempFile();

    std::filesystem::path tmpFilePath = std::filesystem::temp_directory_path() / "tmp.XXXXXX";
    const char* tmpFileName = tmpFilePath.string().c_str();
    std::size_t tmpFileNameLength = tmpFilePath.string().length() + 1;
    char* tmpFile = new char[tmpFileNameLength];
    std::strcpy(tmpFile, tmpFileName);

    int fd = mkstemp(tmpFile);
    if (fd < 0) {
        result.isValid = false;
        delete[] tmpFile;
        return result;
    }

    result.isValid = true;
    result.fd = fd;
    result.fileName = tmpFile;
    delete[] tmpFile;
    return result;
}

void CloseTempFileFd(TempFile& tmpFile)
{
    if (!tmpFile.isValid) {
        return;
    }

    if (tmpFile.fd >= 0) {
        close(tmpFile.fd);
        tmpFile.fd = -1;
    }
}

void DeleteTempFile(TempFile& tmpFile)
{
    if (!tmpFile.isValid) {
        return;
    }

    CloseTempFileFd(tmpFile);

    if (tmpFile.fileName.length() > 0) {
        unlink(tmpFile.fileName.c_str());
        tmpFile.isValid = false;
    }
}

bool CopyFile(
    std::string& error,
    const std::filesystem::path& srcPath,
    const std::filesystem::path& destPath)
{
    if (!std::filesystem::exists(srcPath) || std::filesystem::is_directory(srcPath)) {
        error = "the source file does not exist";
        return false;
    }

    // open the source file stream
    std::ifstream srcFile(srcPath, std::ios::binary);
    if (!srcFile.is_open()) {
        error = "failed to open the stream from the source file";
        return false;
    }

    // open the destination file stream
    std::ofstream destFile(destPath, std::ios::binary);
    if (!destFile.is_open()) {
        error = "failed to open the stream to the destination file";
        return false;
    }

    // stream the data from the source stream to the destination stream
    destFile << srcFile.rdbuf();

    srcFile.close();
    destFile.close();
    return true;
}
