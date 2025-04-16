// CUBE SDK

#ifndef POLICY_EXT_STORAGE_H
#define POLICY_EXT_STORAGE_H

#include <list>
#include <set>

#include <hex/string_util.h>
#include <hex/cli_util.h>
#include <hex/yml_util.h>

struct ExtStorageBackend
{
    bool enabled;
    std::string name;
    std::string driver;
    std::string endpoint;
    std::string account;
    std::string secret;
    std::string pool;

    ExtStorageBackend() : enabled(true), name(""), driver(""),
                          endpoint(""), account(""), secret(""), pool("") {}
};

struct ExtStorageConfig
{
    bool enabled;
    std::list<ExtStorageBackend> backends;
};

class ExtStoragePolicy : public HexPolicy
{
public:
    ExtStoragePolicy() : m_initialized(false), m_yml(NULL) {}

    ~ExtStoragePolicy()
    {
        if (m_yml)
            FiniYml(m_yml);
    }

    const char* policyName() const { return "external_storage"; }
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

        DeleteYmlNode(m_yml, "backends");
        if (m_cfg.backends.size()) {
            AddYmlKey(m_yml, NULL, "backends");
        }

        // seq index starts with 1
        int idx = 1;
        for (auto it = m_cfg.backends.begin(); it != m_cfg.backends.end(); ++it) {
            char seqIdx[64], backendPath[256];

            snprintf(seqIdx, sizeof(seqIdx), "%d", idx);
            snprintf(backendPath, sizeof(backendPath), "backends.%d", idx);

            AddYmlKey(m_yml, "backends", (const char*)seqIdx);
            AddYmlNode(m_yml, backendPath, "enabled", it->enabled ? "true" : "false");
            AddYmlNode(m_yml, backendPath, "name", it->name.c_str());
            AddYmlNode(m_yml, backendPath, "driver", it->driver.c_str());
            AddYmlNode(m_yml, backendPath, "endpoint", it->endpoint.c_str());
            AddYmlNode(m_yml, backendPath, "account", it->account.c_str());
            AddYmlNode(m_yml, backendPath, "secret", it->secret.c_str());
            AddYmlNode(m_yml, backendPath, "pool", it->pool.c_str());
            idx++;
        }

        return (WriteYml(policyFile, m_yml) == 0);
    }

    void updateBackend(ExtStorageBackend *dst, const ExtStorageBackend &src)
    {
        assert(dst->name == src.name);

        dst->enabled = src.enabled;
        dst->driver = src.driver;
        dst->endpoint = src.endpoint;
        dst->account = src.account;
        dst->secret = src.secret;
        dst->pool = src.pool;
    }

    bool setBackend(const ExtStorageBackend &backend)
    {
        if (!m_initialized) {
            return false;
        }

        // update existing backend
        for (auto it = m_cfg.backends.begin(); it != m_cfg.backends.end(); ++it) {
            if (backend.name == it->name) {
                ExtStorageBackend *ptr = &(*it);
                updateBackend(ptr, backend);
                return true;
            }
        }

        // add new backend
        ExtStorageBackend newBackend;
        newBackend.name = backend.name;
        updateBackend(&newBackend, backend);

        m_cfg.backends.push_back(newBackend);

        return true;
    }

    ExtStorageBackend* getBackend(const std::string& name, int* bid)
    {
        *bid = 0;

        if (!m_initialized) {
            return NULL;
        }

        int id = 1;
        for (auto it = m_cfg.backends.begin(); it != m_cfg.backends.end(); ++it) {
            if (name == it->name) {
                ExtStorageBackend *ptr = &(*it);
                *bid = id;
                return ptr;
            }
            id++;
        }

        return NULL;
    }

    bool delBackend(const std::string &name)
    {
        if (!m_initialized) {
            return false;
        }

        for (auto it = m_cfg.backends.begin(); it != m_cfg.backends.end(); ++it) {
            if (name == it->name) {
                m_cfg.backends.erase(it);
                return true;
            }
        }

        return true;
    }

    bool getExtStorageConfig(ExtStorageConfig *config) const
    {
        if (!m_initialized) {
            return false;
        }

        config->enabled = m_cfg.enabled;
        config->backends = m_cfg.backends;

        return true;
    }

private:
    // Has policy been initialized?
    bool m_initialized;

    // The time level 'config' settings
    ExtStorageConfig m_cfg;

    // parsed yml N-ary tree
    GNode *m_yml;

    // Clear out any current configuration
    void clear()
    {
        m_initialized = false;
        m_cfg.enabled = true;
        m_cfg.backends.clear();
    }

    // Method to read the role policy and populate the role member variables
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

        size_t num = SizeOfYmlSeq(m_yml, "backends");
        for (size_t i = 1 ; i <= num ; i++) {
            ExtStorageBackend obj;

            HexYmlParseBool(&obj.enabled, m_yml, "backends.%d.enabled", i);
            HexYmlParseString(obj.name, m_yml, "backends.%d.name", i);
            HexYmlParseString(obj.driver, m_yml, "backends.%d.driver", i);
            HexYmlParseString(obj.endpoint, m_yml, "backends.%d.endpoint", i);
            HexYmlParseString(obj.account, m_yml, "backends.%d.account", i);
            HexYmlParseString(obj.secret, m_yml, "backends.%d.secret", i);
            HexYmlParseString(obj.pool, m_yml, "backends.%d.pool", i);

            m_cfg.backends.push_back(obj);
        }

        //DumpYmlNode(m_yml);

        return true;
    }
};

#endif /* endif POLICY_EXT_STORAGE_H */