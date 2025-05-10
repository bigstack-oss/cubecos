// CUBE SDK

#include <hex/translate_module.h>
#include <hex/log.h>

#include "include/policy_notify_setting.h"

/**
 * Translate the alert setting policy.
 */
static bool
Translate(const char *policy, FILE *settings)
{
    HexLogDebug("translate_alert_setting policy: %s", policy);
    NotifySettingPolicy nsPolicy;
    if (!nsPolicy.load(policy)) {
        HexLogError("Failed to parse policy file %s", policy);
        return false;
    }
    const NotifySettingConfig config = nsPolicy.getConfig();

    HexLogDebug("Processing Alert Notification Setting Config");
    fprintf(settings, "\n# Alert Notification Settings\n");

    // title prefix
    fprintf(settings, "kapacitor.alert.setting.titlePrefix = %s\n", config.titlePrefix.c_str());

    // sender email
    fprintf(settings, "kapacitor.alert.setting.sender.email.host = %s\n", config.sender.email.host.c_str());
    fprintf(settings, "kapacitor.alert.setting.sender.email.port = %s\n", config.sender.email.port.c_str());
    fprintf(settings, "kapacitor.alert.setting.sender.email.username = %s\n", config.sender.email.username.c_str());
    fprintf(settings, "kapacitor.alert.setting.sender.email.password = %s\n", config.sender.email.password.c_str());
    fprintf(settings, "kapacitor.alert.setting.sender.email.from = %s\n", config.sender.email.from.c_str());

    // receiver email
    for (std::size_t i = 0; i < config.receiver.emails.size(); i++) {
        fprintf(settings, "kapacitor.alert.setting.receiver.emails.%zu.address = %s\n", i, config.receiver.emails[i].address.c_str());
        fprintf(settings, "kapacitor.alert.setting.receiver.emails.%zu.note = %s\n", i, config.receiver.emails[i].note.c_str());
    }

    // receiver slack
    for (std::size_t i = 0; i < config.receiver.slacks.size(); i++) {
        fprintf(settings, "kapacitor.alert.setting.receiver.slacks.%zu.url = %s\n", i, config.receiver.slacks[i].url.c_str());
        fprintf(settings, "kapacitor.alert.setting.receiver.slacks.%zu.username = %s\n", i, config.receiver.slacks[i].username.c_str());
        fprintf(settings, "kapacitor.alert.setting.receiver.slacks.%zu.description = %s\n", i, config.receiver.slacks[i].description.c_str());
        fprintf(settings, "kapacitor.alert.setting.receiver.slacks.%zu.workspace = %s\n", i, config.receiver.slacks[i].workspace.c_str());
        fprintf(settings, "kapacitor.alert.setting.receiver.slacks.%zu.channel = %s\n", i, config.receiver.slacks[i].channel.c_str());
    }

    // receiver exec shell
    for (std::size_t i = 0; i < config.receiver.execs.shells.size(); i++) {
        fprintf(settings, "kapacitor.alert.setting.receiver.execs.shells.%zu.name = %s\n", i, config.receiver.execs.shells[i].name.c_str());
    }

    // receiver exec bin
    for (std::size_t i = 0; i < config.receiver.execs.bins.size(); i++) {
        fprintf(settings, "kapacitor.alert.setting.receiver.execs.bins.%zu.name = %s\n", i, config.receiver.execs.bins[i].name.c_str());
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

    NotifySettingPolicy nsPolicy;
    if (!nsPolicy.load(policy)) {
        HexLogError("Failed to parse policy file %s", policy);
        return false;
    }

    // sender email
    for (std::list<NotifyResponse>::const_iterator it = oldConfig.resps.begin(); it != oldConfig.resps.end(); it++) {
        if (it->emailHost != "") {
            nsPolicy.updateSenderEmail(it->emailHost, std::to_string(it->emailPort), it->emailUser, it->emailPass, it->emailFrom);
            break;
        }
    }
    // receiver email
    for (std::list<NotifyResponse>::const_iterator it = oldConfig.resps.begin(); it != oldConfig.resps.end(); it++) {
        if (it->emailTo != "") {
            nsPolicy.addOrUpdateReceiverEmail(it->emailTo, "");
        }
    }
    // receiver slack
    for (std::list<NotifyResponse>::const_iterator it = oldConfig.resps.begin(); it != oldConfig.resps.end(); it++) {
        if (it->slackUrl != "") {
            nsPolicy.addOrUpdateReceiverSlack(it->slackUrl, "", "", "", it->slackChannel);
        }
    }
    // receiver exec
    for (std::list<NotifyResponse>::const_iterator it = oldConfig.resps.begin(); it != oldConfig.resps.end(); it++) {
        if (it->execType != "") {
            if (it->execType == "shell") {
                nsPolicy.addReceiverExecShell(it->name);
            } else if (it->execType == "bin") {
                nsPolicy.addReceiverExecBin(it->name);
            }
        }
    }

    return nsPolicy.save(policy);
}

TRANSLATE_MODULE(alert_setting/alert_setting1_0, 0, 0, Translate, Migrate);
TRANSLATE_MIGRATE_PREVIOUS(alert_setting/alert_setting1_0, alert_resp/alert_resp1_0);
