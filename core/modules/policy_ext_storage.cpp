// CUBE SDK

#include "include/policy_ext_storage.h"

ExtStoragePolicy::ExtStoragePolicy()
    : isInitialized(false)
    , ymlRoot(NULL)
{
}

ExtStoragePolicy::~ExtStoragePolicy()
{
    if (this->ymlRoot) {
        FiniYml(this->ymlRoot);
        this->ymlRoot = NULL;
    }
}

const char*
ExtStoragePolicy::policyName() const
{
    return "external_storage";
}
const char*
ExtStoragePolicy::policyVersion() const
{
    return "1.0";
}

const ExtStorageConfig
ExtStoragePolicy::getConfig() const
{
    return this->config;
}

bool ExtStoragePolicy::load(const char* policyFile)
{
    this->isInitialized = false;
    if (this->ymlRoot) {
        FiniYml(this->ymlRoot);
        this->ymlRoot = NULL;
    }
    this->ymlRoot = InitYml(policyFile);
    if (ReadYml(policyFile, this->ymlRoot) < 0) {
        FiniYml(this->ymlRoot);
        this->ymlRoot = NULL;
        return false;
    }

    HexYmlParseString(this->config.volumeTypeDefault, this->ymlRoot, "volumeType.default");

    std::size_t backendCount = SizeOfYmlSeq(ymlRoot, "backends");
    for (std::size_t i = 1; i <= backendCount; i++) {
        std::string backendName;
        HexYmlParseString(backendName, this->ymlRoot, "backends.%d.name", i);
        this->config.storageBackends.push_back(backendName);
    }

    HexYmlParseBool(&(this->config.imageUseMultipath), this->ymlRoot, "image.multipath.use");
    HexYmlParseBool(&(this->config.imageEnforceMultipath), this->ymlRoot, "image.multipath.enforce");

    this->isInitialized = true;
    return this->isInitialized;
}

bool ExtStoragePolicy::save(const char* policyFile)
{
    if (UpdateYmlValue(this->ymlRoot, "volumeType.default", this->config.volumeTypeDefault.c_str()) != 0) {
        return false;
    }

    if (DeleteYmlNode(this->ymlRoot, "backends") != 0) {
        return false;
    }
    AddYmlKey(this->ymlRoot, NULL, "backends");

    if (this->config.storageBackends.size() == 0) {
        // the yml parser needs to set at least one blank child
        // we would create a blank child if we do not have any
        this->config.storageBackends.push_back("");
    }
    for (std::size_t i = 0; i < this->config.storageBackends.size(); i++) {
        // yml index starts from 1
        std::string ymlIndex = std::to_string(i + 1);
        if (AddYmlKey(this->ymlRoot, "backends", ymlIndex.c_str()) != 0) {
            return false;
        }
        std::string prefix = std::string("backends.").append(ymlIndex);
        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "name", this->config.storageBackends[i].c_str()) != 0) {
            return false;
        }
    }

    if (UpdateYmlValue(this->ymlRoot, "image.multipath.use", this->config.imageUseMultipath ? "true" : "false") != 0) {
        return false;
    }

    if (UpdateYmlValue(this->ymlRoot, "image.multipath.enforce", this->config.imageEnforceMultipath ? "true" : "false") != 0) {
        return false;
    }

    return (WriteYml(policyFile, this->ymlRoot) == 0);
}
