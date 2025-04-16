// HEX SDK

#include <hex/log.h>
#include <hex/yml_util.h>

#include <hex/translate_module.h>

#include "hex/cli_util.h"

// Translate the time policy
static bool
Translate(const char *policy, FILE *settings)
{
    bool status = true;

    HexLogDebug("translate_keystone policy: %s", policy);

    GNode *yml = InitYml("keystone");
    std::string adminPass;

    if (ReadYml(policy, yml) < 0) {
        FiniYml(yml);
        yml = NULL;
        HexLogError("Failed to parse policy file %s", policy);
        return false;
    }

    fprintf(settings, "\n# Keystone Params\n");

    HexYmlParseString(adminPass, yml, "admin-pass");
    fprintf(settings, "keystone.admin.password=%s\n", adminPass.c_str());

    FiniYml(yml);
    yml = NULL;

    return status;

}

TRANSLATE_MODULE(keystone/keystone1_0, 0, 0, Translate, 0);

