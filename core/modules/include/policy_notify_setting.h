// CUBE SDK

#ifndef POLICY_NOTIFY_SETTING_H
#define POLICY_NOTIFY_SETTING_H

#include <vector>

#include <hex/cli_util.h>
#include <hex/yml_util.h>

/**
 * Email sender configurations.
 */
struct NotifySettingSenderEmail {
    std::string host;
    std::string port;
    std::string username;
    std::string password;
    std::string from;
};

/**
 * Sender configurations.
 */
struct NotifySettingSender {
    NotifySettingSenderEmail email;
};

/**
 * Email receiver configurations.
 */
struct NotifySettingReceiverEmail {
    std::string address;
    std::string note;
};

/**
 * Slack receiver configurations.
 */
struct NotifySettingReceiverSlack {
    std::string url;
    std::string username;
    std::string description;
    std::string workspace;
    std::string channel;
};

/**
 * Receiver configurations.
 */
struct NotifySettingReceiver {
    std::vector<NotifySettingReceiverEmail> emails;
    std::vector<NotifySettingReceiverSlack> slacks;
};

/**
 * Setting configurations.
 */
struct NotifySettingConfig {
    NotifySettingSender sender;
    NotifySettingReceiver receiver;
};

/**
 * Policy to set notification setting for alert_setting yml.
 */
class NotifySettingPolicy : public HexPolicy
{
public:
    NotifySettingPolicy();
    ~NotifySettingPolicy();
    const char* policyName() const;
    const char* policyVersion() const;
    /**
     * Load the policy.
     */
    bool load(const char* policyFile);
    /**
     * Save the policy.
     */
    bool save(const char* policyFile);
    /**
     * Add or update the email sender configurations.
     */
    void updateSenderEmail(
        std::string host,
        std::string port,
        std::string username,
        std::string password,
        std::string from
    );
    /**
     * Add or update an email receiver configurations.
     */
    void addOrUpdateReceiverEmail(std::string address, std::string note);
    /**
     * Add or update a slack receiver configurations.
     */
    void addOrUpdateReceiverSlack(
        std::string url,
        std::string username,
        std::string description,
        std::string workspace,
        std::string channel
    );
    /**
     * Delete the email sender.
     */
    void deleteSenderEmail();
    /**
     * Delete the email receiver.
     */
    bool deleteReceiverEmail(std::string address);
    /**
     * Delete the slack receiver.
     */
    bool deleteReceiverSlack(std::string url);
private:
    /**
     * Initialization flag
     */
    bool isInitialized;
    /**
     * Parsed yml N-ary tree
     */
    GNode *ymlRoot;
    /**
     * Configurations
     */
    NotifySettingConfig config;
};


#endif /* endif POLICY_NOTIFY_SETTING_H */
