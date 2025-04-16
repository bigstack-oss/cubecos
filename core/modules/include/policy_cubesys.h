// CUBE SDK

#ifndef POLICY_CUBESYS_H
#define POLICY_CUBESYS_H

#include <hex/cli_util.h>
#include <hex/yml_util.h>
#include <hex/string_util.h>
#include "role_cubesys.h"

class CubeSysPolicy : public HexPolicy
{
public:
    CubeSysPolicy() : m_initialized(false), m_yml(NULL) {}

    ~CubeSysPolicy()
    {
        if (m_yml)
            FiniYml(m_yml);
    }

    const char* policyName() const { return "cubesys"; }
    const char* policyVersion() const { return "1.0"; }

    bool load(const char* policyFile)
    {
        clear();
        m_initialized = parsePolicy(policyFile);
        return m_initialized;
    }

    bool save(const char* policyFile)
    {
        int role = GetCubeRole(m_cfg.role);

        UpdateYmlValue(m_yml, "role", m_cfg.role.c_str());
        UpdateYmlValue(m_yml, "domain", m_cfg.domain.c_str());
        UpdateYmlValue(m_yml, "region", m_cfg.region.c_str());

        if (ControlReq(role)) {
            if (FindYmlNode(m_yml, "controller"))
                UpdateYmlValue(m_yml, "controller", m_cfg.controller.c_str());
            else
                AddYmlNode(m_yml, NULL, "controller", m_cfg.controller.c_str());

            if (FindYmlNode(m_yml, "controller-ip"))
                UpdateYmlValue(m_yml, "controller-ip", m_cfg.controllerIp.c_str());
            else
                AddYmlNode(m_yml, NULL, "controller-ip", m_cfg.controllerIp.c_str());
        }
        else if (IsControl(role)) {
            if (FindYmlNode(m_yml, "controller"))
                UpdateYmlValue(m_yml, "controller", m_cfg.controller.c_str());
            else
                AddYmlNode(m_yml, NULL, "controller", m_cfg.controller.c_str());
            DeleteYmlNode(m_yml, "controller-ip");
        }
        else {
            DeleteYmlNode(m_yml, "controller");
            DeleteYmlNode(m_yml, "controller-ip");
        }

        if (IsControl(role) || IsCompute(role)) {
            if (FindYmlNode(m_yml, "external"))
                UpdateYmlValue(m_yml, "external", m_cfg.external.c_str());
            else
                AddYmlNode(m_yml, NULL, "external", m_cfg.external.c_str());
        }
        else {
            DeleteYmlNode(m_yml, "external");
        }

        UpdateYmlValue(m_yml, "management", m_cfg.mgmt.c_str());

        if (IsCompute(role)) {
            if (FindYmlNode(m_yml, "provider"))
                UpdateYmlValue(m_yml, "provider", m_cfg.provider.c_str());
            else
                AddYmlNode(m_yml, NULL, "provider", m_cfg.provider.c_str());
        }
        else {
            DeleteYmlNode(m_yml, "provider");
        }

        if (IsCompute(role)) {
            if (FindYmlNode(m_yml, "overlay"))
                UpdateYmlValue(m_yml, "overlay", m_cfg.overlay.c_str());
            else
                AddYmlNode(m_yml, NULL, "overlay", m_cfg.overlay.c_str());
        }
        else {
            DeleteYmlNode(m_yml, "overlay");
        }

        if (IsControl(role) || IsCompute(role) || IsStorage(role)) {
            if (FindYmlNode(m_yml, "storage"))
                UpdateYmlValue(m_yml, "storage", m_cfg.storage.c_str());
            else
                AddYmlNode(m_yml, NULL, "storage", m_cfg.storage.c_str());
        }
        else {
            DeleteYmlNode(m_yml, "storage");
        }

        if (FindYmlNode(m_yml, "secret-seed"))
            UpdateYmlValue(m_yml, "secret-seed", m_cfg.seed.c_str());
        else
            AddYmlNode(m_yml, NULL, "secret-seed", m_cfg.seed.c_str());

        if (IsControl(role)) {
            if (FindYmlNode(m_yml, "mgmt-cidr"))
                UpdateYmlValue(m_yml, "mgmt-cidr", m_cfg.mgmtCidr.c_str());
            else
                AddYmlNode(m_yml, NULL, "mgmt-cidr", m_cfg.mgmtCidr.c_str());
        }
        else {
            DeleteYmlNode(m_yml, "mgmt-cidr");
        }

        UpdateYmlValue(m_yml, "saltkey", m_cfg.saltkey ? "true" : "false");
        UpdateYmlValue(m_yml, "ha", m_cfg.ha ? "true" : "false");
        if (m_cfg.ha) {
            if (IsControl(role)) {
                if (FindYmlNode(m_yml, "control-vip"))
                    UpdateYmlValue(m_yml, "control-vip", m_cfg.controlVip.c_str());
                else
                    AddYmlNode(m_yml, NULL, "control-vip", m_cfg.controlVip.c_str());
            }
            else {
                DeleteYmlNode(m_yml, "control-vip");
            }

            if (FindYmlNode(m_yml, "control-hosts"))
                UpdateYmlValue(m_yml, "control-hosts", m_cfg.controlHosts.c_str());
            else
                AddYmlNode(m_yml, NULL, "control-hosts", m_cfg.controlHosts.c_str());

            if (FindYmlNode(m_yml, "control-addrs"))
                UpdateYmlValue(m_yml, "control-addrs", m_cfg.controlAddrs.c_str());
            else
                AddYmlNode(m_yml, NULL, "control-addrs", m_cfg.controlAddrs.c_str());

            if (m_cfg.storageHosts.length()) {
                if (FindYmlNode(m_yml, "storage-hosts"))
                    UpdateYmlValue(m_yml, "storage-hosts", m_cfg.storageHosts.c_str());
                else
                    AddYmlNode(m_yml, NULL, "storage-hosts", m_cfg.storageHosts.c_str());
            }

            if (m_cfg.storageAddrs.length()) {
                if (FindYmlNode(m_yml, "storage-addrs"))
                    UpdateYmlValue(m_yml, "storage-addrs", m_cfg.storageAddrs.c_str());
                else
                    AddYmlNode(m_yml, NULL, "storage-addrs", m_cfg.storageAddrs.c_str());
            }
        }
        else {
            DeleteYmlNode(m_yml, "control-vip");
            DeleteYmlNode(m_yml, "control-hosts");
            DeleteYmlNode(m_yml, "control-addrs");
            DeleteYmlNode(m_yml, "storage-hosts");
            DeleteYmlNode(m_yml, "storage-addrs");
        }

        return (WriteYml(policyFile, m_yml) == 0);
    }

    // Set the role value.
    bool setConfig(const CubeSysConfig &config)
    {
        // Return if not initialized
        if (!m_initialized) {
            return false;
        }

        // Set role
        m_cfg.role = config.role;

        if (config.domain.length())
            m_cfg.domain = config.domain;

        if (config.region.length())
            m_cfg.region = config.region;

        m_cfg.controller = config.controller;
        m_cfg.controllerIp = config.controllerIp;
        m_cfg.external = config.external;
        m_cfg.mgmt = config.mgmt;
        m_cfg.provider = config.provider;
        m_cfg.overlay = config.overlay;
        m_cfg.storage = config.storage;
        m_cfg.seed = config.seed;
        m_cfg.mgmtCidr = config.mgmtCidr;
        m_cfg.ha = config.ha;
        m_cfg.saltkey = config.saltkey;
        m_cfg.controlVip = config.controlVip;
        m_cfg.controlHosts = config.controlHosts;
        m_cfg.controlAddrs = config.controlAddrs;
        m_cfg.storageHosts = config.storageHosts;
        m_cfg.storageAddrs = config.storageAddrs;

        return true;
    }

    bool getConfig(CubeSysConfig* cfg)
    {
        if (!m_initialized || !cfg) {
            return false;
        }

        cfg->role = m_cfg.role;

        if (m_cfg.domain.length())
            cfg->domain = m_cfg.domain;

        if (m_cfg.region.length())
            cfg->region = m_cfg.region;

        cfg->controller = m_cfg.controller;
        cfg->controllerIp = m_cfg.controllerIp;
        cfg->external = m_cfg.external;
        cfg->mgmt = m_cfg.mgmt;
        cfg->provider = m_cfg.provider;
        cfg->overlay = m_cfg.overlay;
        cfg->storage = m_cfg.storage;
        cfg->seed = m_cfg.seed;
        cfg->mgmtCidr = m_cfg.mgmtCidr;
        cfg->ha = m_cfg.ha;
        cfg->saltkey = m_cfg.saltkey;
        cfg->controlVip = m_cfg.controlVip;
        cfg->controlHosts = m_cfg.controlHosts;
        cfg->controlAddrs = m_cfg.controlAddrs;
        cfg->storageHosts = m_cfg.storageHosts;
        cfg->storageAddrs = m_cfg.storageAddrs;

        return true;
    }

    // Retrieve the role value.
    const char* getRole()
    {
        return (m_initialized) ? m_cfg.role.c_str() : "undef";
    }

    const char* getDomain()
    {
        return (m_initialized) ? m_cfg.domain.c_str() : DOMAIN_DEF;
    }

    const char* getRegion()
    {
        return (m_initialized) ? m_cfg.region.c_str() : REGION_DEF;
    }

    const char* getController()
    {
        return (m_initialized && !m_cfg.controller.empty()) ? m_cfg.controller.c_str() : "N/A";
    }

    const char* getControllerIp()
    {
        return (m_initialized && !m_cfg.controllerIp.empty()) ? m_cfg.controllerIp.c_str() : "N/A";
    }

    const char* getExternal()
    {
        return (m_initialized && !m_cfg.external.empty()) ? m_cfg.external.c_str() : "N/A";
    }

    const char* getMgmt()
    {
        return (m_initialized && !m_cfg.mgmt.empty()) ? m_cfg.mgmt.c_str() : "N/A";
    }

    const char* getProvider()
    {
        return (m_initialized && !m_cfg.provider.empty()) ? m_cfg.provider.c_str() : "N/A";
    }

    const char* getOverlay()
    {
        return (m_initialized && !m_cfg.overlay.empty()) ? m_cfg.overlay.c_str() : "N/A";
    }

    const char* getStorage()
    {
        return (m_initialized && !m_cfg.storage.empty()) ? m_cfg.storage.c_str() : "N/A";
    }

    const char* getSecretSeed()
    {
        return (m_initialized && !m_cfg.seed.empty()) ? m_cfg.seed.c_str() : "N/A";
    }

    const char* getMgmtCidr()
    {
        return (m_initialized) ? m_cfg.mgmtCidr.c_str() : MGMT_CIDR_DEF;
    }

    const char* getHA()
    {
        return m_cfg.ha ? "enabled" : "disabled";
    }

    const char* getControlVip()
    {
        return (m_initialized && !m_cfg.controlVip.empty()) ? m_cfg.controlVip.c_str() : "N/A";
    }

    std::string getControlGroup()
    {
        if (!m_initialized || m_cfg.controlHosts.empty() || m_cfg.controlAddrs.empty())
            return "N/A";

        auto hosts = hex_string_util::split(m_cfg.controlHosts, ',');
        auto addrs = hex_string_util::split(m_cfg.controlAddrs, ',');
        if (hosts.size() != addrs.size())
            return "configuration mis-matched";

        std::string group = "";
        for (size_t i = 0 ; i < hosts.size() ; i++) {
            group += hosts[i] + "(" + addrs[i] + ")";
            if (i + 1 < hosts.size())
                group += ",";
        }

        return group;
    }

    std::string getStorageGroup()
    {
        if (!m_initialized || m_cfg.storageHosts.empty() || m_cfg.storageAddrs.empty())
            return "N/A";

        auto hosts = hex_string_util::split(m_cfg.storageHosts, ',');
        auto addrs = hex_string_util::split(m_cfg.storageAddrs, ',');
        if (hosts.size() != addrs.size())
            return "configuration mis-matched";

        std::string group = "";
        for (size_t i = 0 ; i < hosts.size() ; i++) {
            group += hosts[i] + "(" + addrs[i] + ")";
            if (i + 1 < hosts.size())
                group += ",";
        }

        return group;
    }

private:
    // Has policy been initialized?
    bool m_initialized;

    // The time level 'config' settings
    CubeSysConfig m_cfg;

    // parsed yml N-ary tree
    GNode *m_yml;

    // Clear out any current configuration
    void clear()
    {
        m_initialized = false;

        // Reset cube role
        m_cfg.role = "undef";
        m_cfg.domain = DOMAIN_DEF;
        m_cfg.region = REGION_DEF;
        m_cfg.controller = "";
        m_cfg.controllerIp = "";
        m_cfg.external = "";
        m_cfg.mgmt = "IF.1";
        m_cfg.provider = "";
        m_cfg.overlay = "";
        m_cfg.storage = "";
        m_cfg.seed = "";
        m_cfg.mgmtCidr = "";
        m_cfg.ha = false;
        m_cfg.saltkey = false;
        m_cfg.controlVip = "";
        m_cfg.controlHosts = "";
        m_cfg.controlAddrs = "";
        m_cfg.storageHosts = "";
        m_cfg.storageAddrs = "";
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

        HexYmlParseString(m_cfg.role, m_yml, "role");
        HexYmlParseString(m_cfg.domain, m_yml, "domain");
        HexYmlParseString(m_cfg.region, m_yml, "region");
        HexYmlParseString(m_cfg.controller, m_yml, "controller");
        HexYmlParseString(m_cfg.controllerIp, m_yml, "controller-ip");
        HexYmlParseString(m_cfg.external, m_yml, "external");
        HexYmlParseString(m_cfg.mgmt, m_yml, "management");
        HexYmlParseString(m_cfg.provider, m_yml, "provider");
        HexYmlParseString(m_cfg.overlay, m_yml, "overlay");
        HexYmlParseString(m_cfg.storage, m_yml, "storage");
        HexYmlParseString(m_cfg.seed, m_yml, "secret-seed");
        HexYmlParseString(m_cfg.mgmtCidr, m_yml, "mgmt-cidr");
        HexYmlParseBool(&m_cfg.ha, m_yml, "ha");
        HexYmlParseBool(&m_cfg.saltkey, m_yml, "saltkey");
        HexYmlParseString(m_cfg.controlVip, m_yml, "control-vip");
        HexYmlParseString(m_cfg.controlHosts, m_yml, "control-hosts");
        HexYmlParseString(m_cfg.controlAddrs, m_yml, "control-addrs");
        HexYmlParseString(m_cfg.storageHosts, m_yml, "storage-hosts");
        HexYmlParseString(m_cfg.storageAddrs, m_yml, "storage-addrs");

        //DumpYmlNode(m_yml);

        return true;
    }
};

#endif /* endif POLICY_CUBESYS_H */

