// CUBE SDK

#include <hex/translate_module.h>
#include <hex/log.h>

#include "include/policy_notify_trigger.h"

/**
 * Translate the alert trigger policy (alert_resp).
 */
static bool
Translate(const char *policy, FILE *settings)
{
    HexLogDebug("translate_alert_resp policy: %s", policy);
    NotifyTriggerPolicy ntPolicy;
    if (!ntPolicy.load(policy)) {
        HexLogError("Failed to parse policy file %s", policy);
        return false;
    }
    const NotifyTriggerConfig config = ntPolicy.getConfig();

    HexLogDebug("Processing Alert Notification Trigger Config");
    fprintf(settings, "\n# Alert Notification Triggers\n");

    for (std::size_t i = 0; i < config.triggers.size(); i++) {
        fprintf(settings, "kapacitor.alert.resp.%zu.name = %s\n", i, config.triggers[i].name.c_str());
        fprintf(settings, "kapacitor.alert.resp.%zu.enabled = %s\n", i, (config.triggers[i].enabled ? "true" : "false"));
        fprintf(settings, "kapacitor.alert.resp.%zu.topic = %s\n", i, config.triggers[i].topic.c_str());
        // comply with hex tunning parser
        fprintf(settings, "kapacitor.alert.resp.%zu.match = \"%s\"\n", i, hex_string_util::escapeDoubleQuote(config.triggers[i].match).c_str());
        fprintf(settings, "kapacitor.alert.resp.%zu.description = %s\n", i, config.triggers[i].description.c_str());

        // email
        for (std::size_t j = 0; j < config.triggers[i].responses.emails.size(); j++) {
            fprintf(
                settings,
                "kapacitor.alert.resp.%zu.responses.emails.%zu.address = %s\n",
                i,
                j,
                config.triggers[i].responses.emails[j].address.c_str()
            );
        }

        // slack
        for (std::size_t j = 0; j < config.triggers[i].responses.slacks.size(); j++) {
            fprintf(
                settings,
                "kapacitor.alert.resp.%zu.responses.slacks.%zu.url = %s\n",
                i,
                j,
                config.triggers[i].responses.slacks[j].url.c_str()
            );
        }

        // exec shell
        for (std::size_t j = 0; j < config.triggers[i].responses.execs.shells.size(); j++) {
            fprintf(
                settings,
                "kapacitor.alert.resp.%zu.responses.execs.shells.%zu.name = %s\n",
                i,
                j,
                config.triggers[i].responses.execs.shells[j].name.c_str()
            );
        }

        // exec bin
        for (std::size_t j = 0; j < config.triggers[i].responses.execs.bins.size(); j++) {
            fprintf(
                settings,
                "kapacitor.alert.resp.%zu.responses.execs.bins.%zu.name = %s\n",
                i,
                j,
                config.triggers[i].responses.execs.bins[j].name.c_str()
            );
        }
    }

    return true;
}

static bool
Migrate(const char* prevVersion, const char* prevPolicy, const char* policy)
{
    NotifyPolicy oldPolicy;
    if (!oldPolicy.load(prevPolicy)) {
        HexLogError("Failed to parse policy file %s", prevPolicy);
        return false;
    }
    NotifyConfig oldConfig;
    oldPolicy.getNotifyConfig(&oldConfig);

    NotifyTriggerPolicy ntPolicy;
    if (!ntPolicy.load(policy)) {
        HexLogError("Failed to parse policy file %s", policy);
        return false;
    }

    for (std::list<NotifyResponse>::const_iterator it = oldConfig.resps.begin(); it != oldConfig.resps.end(); it++) {
        std::string name = it->name;
        // the old response name, instance-{tenant}-notify
        if (name == "instance--notify") {
            name = "instance-notify";
        }
        std::vector<std::string> emailList;
        if (it->emailTo != "") {
            emailList.push_back(it->emailTo);
        }
        std::vector<std::string> slackList;
        if (it->slackUrl != "") {
            slackList.push_back(it->slackUrl);
        }
        std::vector<std::string> execShellList;
        if (it->execType == "shell") {
            execShellList.push_back(it->name);
        }
        std::vector<std::string> execBinList;
        if (it->execType == "bin") {
            execBinList.push_back(it->name);
        }

        ntPolicy.addOrUpdateTrigger(
            name,
            it->enabled,
            it->topic,
            it->match,
            "",
            emailList,
            slackList,
            execShellList,
            execBinList
        );
    }

    return ntPolicy.save(policy);
}

TRANSLATE_MODULE(alert_resp/alert_resp2_0, 0, 0, Translate, Migrate);
TRANSLATE_REQUIRES(alert_resp/alert_resp2_0, alert_setting/alert_setting1_0);
TRANSLATE_MIGRATE_PREVIOUS(alert_resp/alert_resp2_0, alert_resp/alert_resp1_0);
