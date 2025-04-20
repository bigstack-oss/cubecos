// CUBE SDK

#ifndef POLICY_NOTIFY_TRIGGER_H
#define POLICY_NOTIFY_TRIGGER_H

#include <vector>
#include <set>
#include <sstream>

#include <hex/cli_util.h>
#include <hex/yml_util.h>

#include "include/policy_notify.h"

/**
 * Trigger email configurations.
 */
struct NotifyTriggerResponseEmail
{
    std::string address;
};

/**
 * Trigger slack configurations.
 */
struct NotifyTriggerResponseSlack
{
    std::string url;
};

/**
 * Trigger exec shell configurations.
 */
struct NotifyTriggerResponseExecShell
{
    std::string name;
};

/**
 * Trigger exec bin configurations.
 */
struct NotifyTriggerResponseExecBin
{
    std::string name;
};

/**
 * Trigger exec configurations.
 */
struct NotifyTriggerResponseExec
{
    std::vector<NotifyTriggerResponseExecShell> shells;
    std::vector<NotifyTriggerResponseExecBin> bins;
};

/**
 * Trigger response configurations.
 */
struct NotifyTriggerResponse
{
    std::vector<NotifyTriggerResponseEmail> emails;
    std::vector<NotifyTriggerResponseSlack> slacks;
    NotifyTriggerResponseExec execs;
};

/**
 * Trigger configurations.
 */
struct NotifyTrigger
{
    std::string name;
    bool enabled;
    std::string topic;
    std::string match;
    std::string description;
    NotifyTriggerResponse responses;
};

/**
 * Triggers.
 */
struct NotifyTriggerConfig
{
    std::vector<NotifyTrigger> triggers;
};

/**
 * Policy to set notification trigger for alert_resp yml.
 */
class NotifyTriggerPolicy : public HexPolicy
{
public:
    NotifyTriggerPolicy();
    ~NotifyTriggerPolicy();
    const char* policyName() const;
    const char* policyVersion() const;
    bool isReady() const;
    /**
     * Set the setting policy.
     */
    void setSettingPolicy(const NotifySettingPolicy* settingPolicy);
    /**
     * Load the policy.
     */
    bool load(const char* policyFile);
    /**
     * Save the policy.
     */
    bool save(const char* policyFile);
    /**
     * Add or update a trigger's configurations.
     */
    void addOrUpdateTrigger(
        std::string name,
        bool enabled,
        std::string topic,
        std::string match,
        std::string description,
        const std::vector<std::string>& emails,
        const std::vector<std::string>& slacks,
        const std::vector<std::string>& execShells,
        const std::vector<std::string>& execBins
    );
    /**
     * Delete the trigger by name.
     */
    bool deleteTrigger(std::string name);
    /**
     * Delete email from all triggers by address.
     */
    void deleteEmail(std::string address);
    /**
     * Delete slack from all triggers by url.
     */
    void deleteSlack(std::string url);
    /**
     * Delete exec shell from all triggers by name.
     */
    void deleteExecShell(std::string name);
    /**
     * Delete exec bin from all triggers by name.
     */
    void deleteExecBin(std::string name);
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
    NotifyTriggerConfig config;
    /**
     * Setting policy.
     */
    const NotifySettingPolicy* settingPolicy;
};

#endif /* endif POLICY_NOTIFY_TRIGGER_H */
