// CUBE SDK

#include <hex/log.h>

#include <hex/translate_module.h>
#include <hex/string_util.h>

#include "include/policy_notify.h"

static bool
ProcessNotify(NotifyConfig &cfg, FILE* settings)
{
    HexLogDebug("Processing Alert Notification config");

    if (!cfg.enabled)
        return true;

    int idx = 0;
    for (auto& r : cfg.resps) {
        if (!r.enabled)
            continue;

        fprintf(settings, "kapacitor.alert.resp.%d.name = %s\n", idx, r.name.c_str());
        fprintf(settings, "kapacitor.alert.resp.%d.type = %s\n", idx, r.type.c_str());
        fprintf(settings, "kapacitor.alert.resp.%d.topic = %s\n", idx, r.topic.c_str());
        // comply with hex tunning parser
        fprintf(settings, "kapacitor.alert.resp.%d.match = \"%s\"\n",
                           idx, hex_string_util::escapeDoubleQuote(r.match).c_str());

        if (r.type == "slack") {
            fprintf(settings, "kapacitor.alert.resp.%d.slack.url = %s\n", idx, r.slackUrl.c_str());
            fprintf(settings, "kapacitor.alert.resp.%d.slack.channel = %s\n", idx, r.slackChannel.c_str());
        }
        else if (r.type == "email") {
            fprintf(settings, "kapacitor.alert.resp.%d.email.host = %s\n", idx, r.emailHost.c_str());
            fprintf(settings, "kapacitor.alert.resp.%d.email.port = %lu\n", idx, r.emailPort);
            fprintf(settings, "kapacitor.alert.resp.%d.email.username = %s\n", idx, r.emailUser.c_str());
            fprintf(settings, "kapacitor.alert.resp.%d.email.password = %s\n", idx, r.emailPass.c_str());
            fprintf(settings, "kapacitor.alert.resp.%d.email.from = %s\n", idx, r.emailFrom.c_str());
            fprintf(settings, "kapacitor.alert.resp.%d.email.to = %s\n", idx, r.emailTo.c_str());
        }
        else if (r.type == "exec") {
            fprintf(settings, "kapacitor.alert.resp.%d.exec.type = %s\n", idx, r.execType.c_str());
        }

        idx++;
    }

    return true;
}

// Translate the alert notification policy
static bool
Translate(const char *policy, FILE *settings)
{
    bool status = true;

    HexLogDebug("translate_alert_resp policy: %s", policy);

    GNode *yml = InitYml("alert_resp");
    NotifyConfig cfg;

    if (ReadYml(policy, yml) < 0) {
        FiniYml(yml);
        HexLogError("Failed to parse policy file %s", policy);
        return false;
    }

    HexYmlParseBool(&cfg.enabled, yml, "enabled");

    size_t num = SizeOfYmlSeq(yml, "responses");
    for (size_t i = 1 ; i <= num ; i++) {
        NotifyResponse obj;

        HexYmlParseBool(&obj.enabled, yml, "responses.%d.enabled", i);
        HexYmlParseString(obj.name, yml, "responses.%d.name", i);
        HexYmlParseString(obj.type, yml, "responses.%d.type", i);
        HexYmlParseString(obj.topic, yml, "responses.%d.topic", i);
        HexYmlParseString(obj.match, yml, "responses.%d.match", i);
        if (obj.type == "slack") {
            HexYmlParseString(obj.slackUrl, yml, "responses.%d.url", i);
            HexYmlParseString(obj.slackChannel, yml, "responses.%d.channel", i);
        }
        else if (obj.type == "email") {
            HexYmlParseString(obj.emailHost, yml, "responses.%d.host", i);
            HexYmlParseInt(&obj.emailPort, 0, 65535, yml, "responses.%d.port", i);
            HexYmlParseString(obj.emailUser, yml, "responses.%d.username", i);
            HexYmlParseString(obj.emailPass, yml, "responses.%d.password", i);
            HexYmlParseString(obj.emailFrom, yml, "responses.%d.from", i);
            HexYmlParseString(obj.emailTo, yml, "responses.%d.to", i);
        }
        else if (obj.type == "exec") {
            HexYmlParseString(obj.execType, yml, "responses.%d.exectype", i);
        }

        cfg.resps.push_back(obj);
    }

    fprintf(settings, "\n# Alert Notification Settings\n");
    ProcessNotify(cfg, settings);

    FiniYml(yml);

    return status;
}

TRANSLATE_MODULE(alert_resp/alert_resp1_0, 0, 0, Translate, 0);
