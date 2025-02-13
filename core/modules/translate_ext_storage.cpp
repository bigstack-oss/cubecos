// CUBE SDK

#include <hex/log.h>

#include <hex/translate_module.h>

#include "include/policy_ext_storage.h"

static bool
ProcessExtStorage(ExtStorageConfig &cfg, FILE* settings)
{
    HexLogDebug("Processing External Storage config");

    if (!cfg.enabled)
        return true;

    int idx = 0;
    for (auto& b : cfg.backends) {
        if (!b.enabled)
            continue;

        fprintf(settings, "cinder.external.%d.name = %s\n", idx, b.name.c_str());
        fprintf(settings, "cinder.external.%d.driver = %s\n", idx, b.driver.c_str());
        fprintf(settings, "cinder.external.%d.endpoint = %s\n", idx, b.endpoint.c_str());
        fprintf(settings, "cinder.external.%d.account = %s\n", idx, b.account.c_str());
        fprintf(settings, "cinder.external.%d.secret = %s\n", idx, b.secret.c_str());
        fprintf(settings, "cinder.external.%d.pool = %s\n", idx, b.pool.c_str());
        idx++;
    }

    return true;
}

// Translate the external storage policy
static bool
Translate(const char *policy, FILE *settings)
{
    bool status = true;

    HexLogDebug("translate_external_storage policy: %s", policy);

    GNode *yml = InitYml("external_storage");
    ExtStorageConfig cfg;

    if (ReadYml(policy, yml) < 0) {
        FiniYml(yml);
        HexLogError("Failed to parse policy file %s", policy);
        return false;
    }

    HexYmlParseBool(&cfg.enabled, yml, "enabled");

    size_t num = SizeOfYmlSeq(yml, "backends");
    for (size_t i = 1 ; i <= num ; i++) {
        ExtStorageBackend obj;

        HexYmlParseBool(&obj.enabled, yml, "backends.%d.enabled", i);
        HexYmlParseString(obj.name, yml, "backends.%d.name", i);
        HexYmlParseString(obj.driver, yml, "backends.%d.driver", i);
        HexYmlParseString(obj.endpoint, yml, "backends.%d.endpoint", i);
        HexYmlParseString(obj.account, yml, "backends.%d.account", i);
        HexYmlParseString(obj.secret, yml, "backends.%d.secret", i);
        HexYmlParseString(obj.pool, yml, "backends.%d.pool", i);

        cfg.backends.push_back(obj);
    }

    fprintf(settings, "\n# External Storage Settings\n");
    ProcessExtStorage(cfg, settings);

    FiniYml(yml);

    return status;
}

TRANSLATE_MODULE(external_storage/external_storage1_0, 0, 0, Translate, 0);

