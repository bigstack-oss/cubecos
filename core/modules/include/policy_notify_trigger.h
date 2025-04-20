// CUBE SDK

#ifndef POLICY_NOTIFY_TRIGGER_H
#define POLICY_NOTIFY_TRIGGER_H

#include <vector>
#include <set>
#include <sstream>

#include <hex/cli_util.h>
#include <hex/yml_util.h>

struct NotifyTriggerResponseEmail
{
    std::string address;
};

struct NotifyTriggerResponseSlack
{
    std::string url;
};

struct NotifyTriggerResponseExecShell
{
    std::string name;
};

struct NotifyTriggerResponseExecBin
{
    std::string name;
};

struct NotifyTriggerResponseExec
{
    std::vector<NotifyTriggerResponseExecShell> shells;
    std::vector<NotifyTriggerResponseExecBin> bins;
};

struct NotifyTriggerResponse
{
    std::vector<NotifyTriggerResponseEmail> emails;
    std::vector<NotifyTriggerResponseSlack> slacks;
    NotifyTriggerResponseExec execs;
};

struct NotifyTrigger
{
    std::string name;
    bool enabled;
    std::string topic;
    std::string match;
    std::string description;
    NotifyTriggerResponse responses;
};

struct NotifyTriggerConfig
{
    std::vector<NotifyTrigger> triggers;
};

class NotifyTriggerPolicy : public HexPolicy
{
public:
    NotifyTriggerPolicy();
    ~NotifyTriggerPolicy();
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
};

#endif /* endif POLICY_NOTIFY_TRIGGER_H */
