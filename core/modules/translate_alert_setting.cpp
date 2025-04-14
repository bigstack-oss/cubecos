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

    // sender email
    fprintf(settings, "kapacitor.alert.setting.sender.email.host = %s\n", config.sender.email.host);
    fprintf(settings, "kapacitor.alert.setting.sender.email.port = %s\n", config.sender.email.port);
    fprintf(settings, "kapacitor.alert.setting.sender.email.username = %s\n", config.sender.email.username);
    fprintf(settings, "kapacitor.alert.setting.sender.email.password = %s\n", config.sender.email.password);
    fprintf(settings, "kapacitor.alert.setting.sender.email.from = %s\n", config.sender.email.from);

    // receiver email
    for (std::size_t i = 0; i < config.receiver.emails.size(); i++) {
        fprintf(settings, "kapacitor.alert.setting.receiver.emails.%d.address = %s\n", i, config.receiver.emails[i].address);
        fprintf(settings, "kapacitor.alert.setting.receiver.emails.%d.note = %s\n", i, config.receiver.emails[i].note);
    }

    // receiver slack
    for (std::size_t i = 0; i < config.receiver.slacks.size(); i++) {
        fprintf(settings, "kapacitor.alert.setting.receiver.slacks.%d.url = %s\n", i, config.receiver.slacks[i].url);
        fprintf(settings, "kapacitor.alert.setting.receiver.slacks.%d.username = %s\n", i, config.receiver.slacks[i].username);
        fprintf(settings, "kapacitor.alert.setting.receiver.slacks.%d.description = %s\n", i, config.receiver.slacks[i].description);
        fprintf(settings, "kapacitor.alert.setting.receiver.slacks.%d.workspace = %s\n", i, config.receiver.slacks[i].workspace);
        fprintf(settings, "kapacitor.alert.setting.receiver.slacks.%d.channel = %s\n", i, config.receiver.slacks[i].channel);
    }

    return true;
}

TRANSLATE_MODULE(alert_setting/alert_setting1_0, 0, 0, Translate, 0);
