// CUBE SDK

#ifndef POLICY_NOTIFY_H
#define POLICY_NOTIFY_H

#include <assert.h>
#include <list>

#include <hex/parse.h>
#include <hex/string_util.h>
#include <hex/cli_util.h>
#include <hex/yml_util.h>

class NotifySettingPolicy;
class NotifyTriggerPolicy;

struct NotifyResponse
{
    bool enabled;
    std::string name;
    std::string type;
    std::string topic;
    std::string match;
    std::string slackUrl;
    std::string slackChannel;
    std::string emailHost;
    int64_t emailPort;
    std::string emailUser;
    std::string emailPass;
    std::string emailFrom;
    std::string emailTo;
    std::string execType;

    NotifyResponse();
};

struct NotifyConfig
{
    bool enabled;
    std::list<NotifyResponse> resps;
};

/**
 * The old notification policy, only used for migration.
 */
class NotifyPolicy : public HexPolicy
{
public:
    NotifyPolicy();
    ~NotifyPolicy();
    const char* policyName() const;
    const char* policyVersion() const;

    bool load(const char* policyFile);
    bool save(const char* policyFile);
    bool getNotifyConfig(NotifyConfig *config) const;

private:
    // Has policy been initialized?
    bool m_initialized;

    // The time level 'config' settings
    NotifyConfig m_cfg;

    // parsed yml N-ary tree
    GNode *m_yml;

    // Clear out any current configuration
    void clear();

    // Method to read the role policy and populate the role member variables
    bool parsePolicy(const char* policyFile);
};

#endif /* endif POLICY_NOTIFY_H */
