// CUBE SDK

#include "include/policy_ext_storage.h"
#include <hex/log.h>
#include <hex/translate_module.h>

// Translate the external storage policy
static bool
Translate(const char* policyFile, FILE* settings)
{
    HexLogDebug("translate_external_storage policy: %s", policyFile);
    ExtStoragePolicy policy;
    if (!policy.load(policyFile)) {
        HexLogError("Failed to parse policy file %s", policyFile);
        return false;
    }
    const ExtStorageConfig config = policy.getConfig();

    HexLogDebug("Processing External Storage config");
    fprintf(settings, "\n# External Storage Settings\n");

    fprintf(settings, "cinder.storage.volumeType.default = %s\n", config.volumeTypeDefault.c_str());

    for (std::size_t i = 0; i < config.storageBackends.size(); i++) {
        fprintf(settings, "cinder.storage.backend.%zu.name = %s\n", i, config.storageBackends[i].c_str());
    }

    fprintf(settings, "glance.cinder.useMultipath = %s\n", (config.imageUseMultipath ? "true" : "false"));
    fprintf(settings, "glance.cinder.enforceMultipath = %s\n", (config.imageEnforceMultipath ? "true" : "false"));

    return true;
}

TRANSLATE_MODULE(external_storage/external_storage1_0, 0, 0, Translate, 0);
