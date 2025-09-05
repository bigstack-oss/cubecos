// CUBE SDK

#ifndef POLICY_EXT_STORAGE_H
#define POLICY_EXT_STORAGE_H

#include <hex/cli_util.h>
#include <hex/yml_util.h>
#include <vector>

struct ExtStorageConfig {
    std::string volumeTypeDefault;
    std::vector<std::string> storageBackends;
};

class ExtStoragePolicy : public HexPolicy {
public:
    ExtStoragePolicy();
    ~ExtStoragePolicy();
    const char* policyName() const;
    const char* policyVersion() const;
    const ExtStorageConfig getConfig() const;
    /**
     * Load the policy.
     */
    bool load(const char* policyFile);
    /**
     * Save the policy.
     */
    bool save(const char* policyFile);

private:
    /**
     * Initialization flag
     */
    bool isInitialized;
    /**
     * Parsed yml N-ary tree
     */
    GNode* ymlRoot;
    /**
     * Configurations
     */
    ExtStorageConfig config;
};

#endif /* endif POLICY_EXT_STORAGE_H */