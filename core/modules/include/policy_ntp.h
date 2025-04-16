// CUBE SDK

#ifndef POLICY_NTP_H_
#define POLICY_NTP_H_

#include <hex/yml_util.h>
#include <hex/cli_util.h>

struct NtpConfig
{
    bool enabled;
    bool debug;
    std::string server;
};

class NtpPolicy : public HexPolicy
{
public:
    NtpPolicy() : m_initialized(false), m_yml(NULL) {}

    ~NtpPolicy()
    {
        if (m_yml)
            FiniYml(m_yml);
    }

    const char* policyName() const { return "ntp"; }
    const char* policyVersion() const { return "1.0"; }

    bool load(const char* policyFile)
    {
        clear();
        m_initialized = parsePolicy(policyFile);
        return m_initialized;
    }

    bool save(const char* policyFile)
    {
        UpdateYmlValue(m_yml, "enabled", m_cfg.enabled ? "true" : "false");
        UpdateYmlValue(m_yml, "debug", m_cfg.debug ? "true" : "false");
        UpdateYmlValue(m_yml, "server", m_cfg.server.c_str());

        return (WriteYml(policyFile, m_yml) == 0);
    }

    bool setServer(const std::string &server)
    {
        if (!m_initialized) {
            return false;
        }

        m_cfg.server = server;
        return true;
    }

    const char* getServer(void)
    {
        return (m_initialized) ? m_cfg.server.c_str() : "err";
    }

private:
    bool m_initialized;

    NtpConfig m_cfg;

    GNode *m_yml;

    void clear()
    {
        m_initialized = false;

        m_cfg.enabled = true;
        m_cfg.debug = false;
        m_cfg.server = "";
    }

    bool parsePolicy(const char* policyFile)
    {
        if (m_yml) {
            FiniYml(m_yml);
        }
        m_yml = InitYml(policyFile);

        if (ReadYml(policyFile, m_yml) < 0) {
            FiniYml(m_yml);
            return false;
        }

        HexYmlParseBool(&m_cfg.enabled, m_yml, "enabled");
        HexYmlParseBool(&m_cfg.debug, m_yml, "debug");
        HexYmlParseString(m_cfg.server, m_yml, "server");

        //DumpYmlNode(m_yml);

        return true;
    }
};

#endif /* endif POLICY_NTP_H_ */

