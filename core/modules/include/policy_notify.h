// CUBE SDK

#ifndef POLICY_NOTIFY_H
#define POLICY_NOTIFY_H

#include <list>

#include <hex/parse.h>
#include <hex/string_util.h>
#include <hex/cli_util.h>
#include <hex/yml_util.h>

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

    NotifyResponse() : enabled(true), name(""), type(""), topic(""), match(""),
                       slackUrl(""), slackChannel(""),
                       emailHost(""), emailPort(0), emailUser(""), emailPass(""), emailFrom(""), emailTo(""),
                       execType("") {}
};

struct NotifyConfig
{
    bool enabled;
    std::list<NotifyResponse> resps;
};

class NotifyPolicy : public HexPolicy
{
public:
    NotifyPolicy() : m_initialized(false), m_yml(NULL) {}

    ~NotifyPolicy()
    {
        if (m_yml)
            FiniYml(m_yml);
    }

    const char* policyName() const { return "alert_resp"; }
    const char* policyVersion() const { return "1.0"; }

    std::string escapeDoubleQuote(const std::string &str)
    {
        // 1. Escape each single quoat(") to '\"'
        std::stringstream out;
        for (std::string::const_iterator it = str.begin(); it != str.end(); it++) {
            if (*it == '"')
                out << "\\\"";
            else
                out << *it;
        }
        return out.str();
    }

    bool load(const char* policyFile)
    {
        clear();
        m_initialized = parsePolicy(policyFile);
        return m_initialized;
    }

    bool save(const char* policyFile)
    {
        UpdateYmlValue(m_yml, "enabled", m_cfg.enabled ? "true" : "false");

        DeleteYmlNode(m_yml, "responses");
        if (m_cfg.resps.size()) {
            AddYmlKey(m_yml, NULL, "responses");
        }

        // seq index starts with 1
        int idx = 1;
        for (auto it = m_cfg.resps.begin(); it != m_cfg.resps.end(); ++it) {
            char seqIdx[64], respPath[256];

            snprintf(seqIdx, sizeof(seqIdx), "%d", idx);
            snprintf(respPath, sizeof(respPath), "responses.%d", idx);

            AddYmlKey(m_yml, "responses", (const char*)seqIdx);
            AddYmlNode(m_yml, respPath, "enabled", it->enabled ? "true" : "false");
            AddYmlNode(m_yml, respPath, "name", it->name.c_str());
            AddYmlNode(m_yml, respPath, "type", it->type.c_str());
            AddYmlNode(m_yml, respPath, "topic", it->topic.c_str());

            // comply with yaml format
            std::string match = "\"" + escapeDoubleQuote(it->match) + "\"";
            AddYmlNode(m_yml, respPath, "match", match.c_str());

            if (it->type == "slack") {
                AddYmlNode(m_yml, respPath, "url", it->slackUrl.c_str());
                AddYmlNode(m_yml, respPath, "channel", it->slackChannel.c_str());
            }
            if (it->type == "email") {
                AddYmlNode(m_yml, respPath, "host", it->emailHost.c_str());
                AddYmlNode(m_yml, respPath, "port", std::to_string(it->emailPort).c_str());
                AddYmlNode(m_yml, respPath, "username", it->emailUser.c_str());
                AddYmlNode(m_yml, respPath, "password", it->emailPass.c_str());
                AddYmlNode(m_yml, respPath, "from", it->emailFrom.c_str());
                AddYmlNode(m_yml, respPath, "to", it->emailTo.c_str());
            }
            if (it->type == "exec") {
                AddYmlNode(m_yml, respPath, "exectype", it->execType.c_str());
            }

            idx++;
        }

        return (WriteYml(policyFile, m_yml) == 0);
    }

    void updateResponse(NotifyResponse *dst, const NotifyResponse &src)
    {
        assert(dst->name == src.name);

        dst->enabled = src.enabled;
        dst->name = src.name;
        dst->type = src.type;
        dst->topic = src.topic;
        dst->match = src.match;
        if (dst->type == "slack") {
            dst->slackUrl = src.slackUrl;
            dst->slackChannel = src.slackChannel;
        }
        if (dst->type == "email") {
            dst->emailHost = src.emailHost;
            dst->emailPort = src.emailPort;
            dst->emailUser = src.emailUser;
            dst->emailPass = src.emailPass;
            dst->emailFrom = src.emailFrom;
            dst->emailTo = src.emailTo;
        }
        if (dst->type == "exec") {
            dst->execType = src.execType;
        }
    }

    bool setResponse(const NotifyResponse &resp)
    {
        if (!m_initialized) {
            return false;
        }

        // update existing resp
        for (auto it = m_cfg.resps.begin(); it != m_cfg.resps.end(); ++it) {
            if (resp.name == it->name) {
                NotifyResponse *ptr = &(*it);
                updateResponse(ptr, resp);
                return true;
            }
        }

        // add new resp
        NotifyResponse newResponse;
        newResponse.name = resp.name;
        updateResponse(&newResponse, resp);

        m_cfg.resps.push_back(newResponse);

        return true;
    }

    NotifyResponse* getResponse(const std::string& name, int* rid)
    {
        *rid = 0;

        if (!m_initialized) {
            return NULL;
        }

        int id = 1;
        for (auto it = m_cfg.resps.begin(); it != m_cfg.resps.end(); ++it) {
            if (name == it->name) {
                NotifyResponse *ptr = &(*it);
                *rid = id;
                return ptr;
            }
            id++;
        }

        return NULL;
    }

    bool delResponse(const std::string &name)
    {
        if (!m_initialized) {
            return false;
        }

        for (auto it = m_cfg.resps.begin(); it != m_cfg.resps.end(); ++it) {
            if (name == it->name) {
                m_cfg.resps.erase(it);
                return true;
            }
        }

        return true;
    }

    bool getNotifyConfig(NotifyConfig *config) const
    {
        if (!m_initialized) {
            return false;
        }

        config->enabled = m_cfg.enabled;
        config->resps = m_cfg.resps;

        return true;
    }

private:
    // Has policy been initialized?
    bool m_initialized;

    // The time level 'config' settings
    NotifyConfig m_cfg;

    // parsed yml N-ary tree
    GNode *m_yml;

    // Clear out any current configuration
    void clear()
    {
        m_initialized = false;
        m_cfg.enabled = true;
        m_cfg.resps.clear();
    }

    // Method to read the role policy and populate the role member variables
    bool parsePolicy(const char* policyFile)
    {
        if (m_yml != nullptr) {
            FiniYml(m_yml);
        }
        m_yml = InitYml(policyFile);

        if (ReadYml(policyFile, m_yml) < 0) {
            FiniYml(m_yml);
            return false;
        }

        HexYmlParseBool(&m_cfg.enabled, m_yml, "enabled");

        size_t num = SizeOfYmlSeq(m_yml, "responses");
        for (size_t i = 1 ; i <= num ; i++) {
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

        //DumpYmlNode(m_yml);

        return true;
    }
};

#endif /* endif POLICY_NOTIFY_H */

