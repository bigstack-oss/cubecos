// HEX SDK

#include <hex/log.h>
#include <hex/yml_util.h>

#include <hex/translate_module.h>

#include "hex/cli_util.h"

// Translate the rancher policy
static bool
Translate(const char *policy, FILE *settings)
{
    bool status = true;

    HexLogDebug("translate_rancher policy: %s", policy);

    GNode *yml = InitYml("rancher");
    bool enabled;

    if (ReadYml(policy, yml) < 0) {
        FiniYml(yml);
        HexLogError("Failed to parse policy file %s", policy);
        return false;
    }

    fprintf(settings, "\n# Rancher Params\n");

    HexYmlParseBool(&enabled, yml, "enabled");
    fprintf(settings, "rancher.enabled = %s\n", enabled ? "true" : "false");

    FiniYml(yml);

    return status;

}

TRANSLATE_MODULE(rancher/rancher1_0, 0, 0, Translate, 0);

