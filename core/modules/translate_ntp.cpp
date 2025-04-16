// HEX SDK

#include <hex/log.h>
#include <hex/yml_util.h>

#include <hex/translate_module.h>
#include "include/policy_ntp.h"

static bool
Translate(const char *policy, FILE *settings)
{
    bool status = true;

    HexLogDebug("translate_ntp policy: %s", policy);

    GNode *yml = InitYml("ntp");
    NtpConfig cfg;

    if (ReadYml(policy, yml) < 0) {
        FiniYml(yml);
        yml = NULL;
        HexLogError("Failed to parse policy file %s", policy);
        return false;
    }

    HexYmlParseBool(&cfg.enabled, yml, "enabled");
    HexYmlParseBool(&cfg.debug, yml, "debug");
    HexYmlParseString(cfg.server, yml, "server");

    fprintf(settings, "\n# NTP Tuning Params\n");
    fprintf(settings, "ntp.enabled = %s\n", cfg.enabled ? "true" : "false");
    fprintf(settings, "ntp.debug.enabled = %s\n", cfg.debug ? "true" : "false");
    fprintf(settings, "ntp.server = %s\n", cfg.server.c_str());

    FiniYml(yml);
    yml = NULL;

    return status;
}

TRANSLATE_MODULE(ntp/ntp1_0, 0, 0, Translate, 0);

