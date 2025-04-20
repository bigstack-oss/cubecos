// CUBE SDK

#ifndef POLICY_NOTIFY_SETTING_H
#define POLICY_NOTIFY_SETTING_H

#include <vector>
#include <set>

#include <hex/cli_util.h>
#include <hex/yml_util.h>

#include "include/policy_notify.h"

/**
 * Email sender configurations.
 */
struct NotifySettingSenderEmail
{
    std::string host;
    std::string port;
    std::string username;
    std::string password;
    std::string from;
};

/**
 * Sender configurations.
 */
struct NotifySettingSender
{
    NotifySettingSenderEmail email;
};

/**
 * Email receiver configurations.
 */
struct NotifySettingReceiverEmail
{
    std::string address;
    std::string note;
};

/**
 * Slack receiver configurations.
 */
struct NotifySettingReceiverSlack
{
    std::string url;
    std::string username;
    std::string description;
    std::string workspace;
    std::string channel;
};

/**
 * Shell exec receiver configurations.
 */
struct NotifySettingReceiverExecShell
{
    std::string name;
};

/**
 * Binary exec receiver configurations.
 */
struct NotifySettingReceiverExecBin
{
    std::string name;
};

/**
 * Exec receiver configurations.
 */
struct NotifySettingReceiverExec
{
    std::vector<NotifySettingReceiverExecShell> shells;
    std::vector<NotifySettingReceiverExecBin> bins;
};

/**
 * Receiver configurations.
 */
struct NotifySettingReceiver
{
    std::vector<NotifySettingReceiverEmail> emails;
    std::vector<NotifySettingReceiverSlack> slacks;
    NotifySettingReceiverExec execs;
};

/**
 * Setting configurations.
 */
struct NotifySettingConfig
{
    std::string titlePrefix;
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
    bool isReady() const;
    const NotifySettingConfig getConfig() const;
    /**
     * Set the trigger policy.
     */
    void setTriggerPolicy(NotifyTriggerPolicy* triggerPolicy);
    /**
     * Load the policy.
     */
    bool load(const char* policyFile);
    /**
     * Save the policy.
     */
    bool save(const char* policyFile);
    /**
     * Check if the email address matches one of the email receiver.
     */
    bool hasReceiverEmail(std::string address) const;
    /**
     * Check if the slack url matches one of the slack receiver.
     */
    bool hasReceiverSlack(std::string url) const;
    /**
     * Check if the exec shell name matches one of the exec shell receiver.
     */
    bool hasReceiverExecShell(std::string name) const;
    /**
     * Check if the exec bin name matches one of the exec bin receiver.
     */
    bool hasReceiverExecBin(std::string name) const;
    /**
     * Add or update the email sender's configurations.
     */
    void updateSenderEmail(
        std::string host,
        std::string port,
        std::string username,
        std::string password,
        std::string from
    );
    /**
     * Add or update an email receiver's configurations.
     */
    void addOrUpdateReceiverEmail(std::string address, std::string note);
    /**
     * Add or update a slack receiver's configurations.
     */
    void addOrUpdateReceiverSlack(
        std::string url,
        std::string username,
        std::string description,
        std::string workspace,
        std::string channel
    );
    /**
     * Add an exec shell's configurations.
     */
    void addReceiverExecShell(std::string name);
    /**
     * Add an exec bin's configurations.
     */
    void addReceiverExecBin(std::string name);
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
    /**
     * Delete the exec shell receiver.
     */
    bool deleteReceiverExecShell(std::string name);
    /**
     * Delete the exec bin receiver.
     */
    bool deleteReceiverExecBin(std::string name);
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
    /**
     * Trigger policy.
     */
    NotifyTriggerPolicy* triggerPolicy;
};

#endif /* endif POLICY_NOTIFY_SETTING_H */
