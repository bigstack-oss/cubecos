// CUBE SDK

#include "include/policy_notify.h"

NotifyResponse::NotifyResponse():
    enabled(true),
    name(""),
    type(""),
    topic(""),
    match(""),
    slackUrl(""),
    slackChannel(""),
    emailHost(""),
    emailPort(0),
    emailUser(""),
    emailPass(""),
    emailFrom(""),
    emailTo(""),
    execType("")
{}

NotifyPolicy::NotifyPolicy():
    m_initialized(false),
    m_yml(NULL)
{}

NotifyPolicy::~NotifyPolicy()
{
    if (m_yml) {
        FiniYml(m_yml);
        m_yml = NULL;
    }
}

const char*
NotifyPolicy::policyName() const
{
    return "alert_resp";
}

const char*
NotifyPolicy::policyVersion() const
{
    return "1.0";
}

bool
NotifyPolicy::load(const char* policyFile)
{
    clear();
    m_initialized = parsePolicy(policyFile);
    return m_initialized;
}

bool
NotifyPolicy::save(const char* policyFile)
{
    return true;
}

bool
NotifyPolicy::getNotifyConfig(NotifyConfig *config) const
{
    if (!m_initialized) {
        return false;
    }

    config->enabled = m_cfg.enabled;
    config->resps = m_cfg.resps;
    return true;
}

void
NotifyPolicy::clear()
{
    m_initialized = false;
    m_cfg.enabled = true;
    m_cfg.resps.clear();
}

bool
NotifyPolicy::parsePolicy(const char* policyFile)
{
    if (m_yml) {
        FiniYml(m_yml);
        m_yml = NULL;
    }
    m_yml = InitYml(policyFile);

    if (ReadYml(policyFile, m_yml) < 0) {
        FiniYml(m_yml);
        m_yml = NULL;
        return false;
    }

    HexYmlParseBool(&m_cfg.enabled, m_yml, "enabled");

    std::size_t num = SizeOfYmlSeq(m_yml, "responses");
    for (std::size_t i = 1 ; i <= num ; i++) {
        NotifyResponse obj;

        HexYmlParseBool(&obj.enabled, m_yml, "responses.%d.enabled", i);
        HexYmlParseString(obj.name, m_yml, "responses.%d.name", i);
        HexYmlParseString(obj.type, m_yml, "responses.%d.type", i);
        HexYmlParseString(obj.topic, m_yml, "responses.%d.topic", i);
        HexYmlParseString(obj.match, m_yml, "responses.%d.match", i);
        if (obj.type == "slack") {
            HexYmlParseString(obj.slackUrl, m_yml, "responses.%d.url", i);
            HexYmlParseString(obj.slackChannel, m_yml, "responses.%d.channel", i);
        }
        if (obj.type == "email") {
            HexYmlParseString(obj.emailHost, m_yml, "responses.%d.host", i);
            HexYmlParseInt(&obj.emailPort, 0, 65535, m_yml, "responses.%d.port", i);
            HexYmlParseString(obj.emailUser, m_yml, "responses.%d.username", i);
            HexYmlParseString(obj.emailPass, m_yml, "responses.%d.password", i);
            HexYmlParseString(obj.emailFrom, m_yml, "responses.%d.from", i);
            HexYmlParseString(obj.emailTo, m_yml, "responses.%d.to", i);
        }
        if (obj.type == "exec") {
            HexYmlParseString(obj.execType, m_yml, "responses.%d.exectype", i);
        }

        m_cfg.resps.push_back(obj);
    }

    return true;
}
