// CUBE SDK

#ifndef POLICY_QOS_H
#define POLICY_QOS_H

#include <list>
#include <set>

#include <hex/string_util.h>
#include <hex/cli_util.h>
#include <hex/yml_util.h>

#define MAX_RATE 100000000L // 100Gbps

enum {
    QOS_RULE_SHARED = 0,
    QOS_RULE_PER_IP,
    QOS_RULE_TYPE_MAX = QOS_RULE_PER_IP
};

struct QosRule
{
    bool enabled;
    std::string name;
    std::string label;
    std::string ipRange;
    uint64_t ingressRate;
    uint64_t ingressCeil;
    uint64_t egressRate;
    uint64_t egressCeil;
    uint64_t burst;
    uint64_t vlan;
    int type;
    QosRule() : enabled(true), name(""), label(""), ipRange(""),
                ingressRate(0), ingressCeil(0), egressRate(0), egressCeil(0),
                burst(0), vlan(0), type(QOS_RULE_SHARED) {}
};

struct QosConfig
{
    bool enabled;
    std::list<QosRule> rules;
};

class QosPolicy : public HexPolicy
{
public:
    QosPolicy() : m_initialized(false), m_yml(NULL) {}

    ~QosPolicy()
    {
        if (m_yml) {
            FiniYml(m_yml);
            m_yml = NULL;
        }
    }

    const char* policyName() const { return "qos"; }
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

        DeleteYmlNode(m_yml, "rules");
        if (m_cfg.rules.size()) {
            AddYmlKey(m_yml, NULL, "rules");
        }

        // seq index starts with 1
        int idx = 1;
        for (auto it = m_cfg.rules.begin(); it != m_cfg.rules.end(); ++it) {
            char seqIdx[64], rulePath[256];

            snprintf(seqIdx, sizeof(seqIdx), "%d", idx);
            snprintf(rulePath, sizeof(rulePath), "rules.%d", idx);

            AddYmlKey(m_yml, "rules", (const char*)seqIdx);
            AddYmlNode(m_yml, rulePath, "enabled", it->enabled ? "true" : "false");
            AddYmlNode(m_yml, rulePath, "type", std::to_string(it->type).c_str());
            AddYmlNode(m_yml, rulePath, "name", it->name.c_str());
            AddYmlNode(m_yml, rulePath, "label", it->label.c_str());
            AddYmlNode(m_yml, rulePath, "ip-range", it->ipRange.c_str());
            AddYmlNode(m_yml, rulePath, "egress-rate", hex_string_util::toString(it->egressRate).c_str());
            AddYmlNode(m_yml, rulePath, "egress-ceil", hex_string_util::toString(it->egressCeil).c_str());
            AddYmlNode(m_yml, rulePath, "ingress-rate", hex_string_util::toString(it->ingressRate).c_str());
            AddYmlNode(m_yml, rulePath, "ingress-ceil", hex_string_util::toString(it->ingressCeil).c_str());
            AddYmlNode(m_yml, rulePath, "burst", hex_string_util::toString(it->burst).c_str());
            AddYmlNode(m_yml, rulePath, "vlan", hex_string_util::toString(it->vlan).c_str());

            idx++;
        }

        return (WriteYml(policyFile, m_yml) == 0);
    }

    void updateQosRule(QosRule *dst, const QosRule &src)
    {
        assert(dst->name == src.name);

        dst->enabled = src.enabled;
        dst->type = src.type;
        dst->label = src.label;
        dst->ipRange = src.ipRange;
        dst->ingressRate = src.ingressRate;
        dst->ingressCeil = src.ingressCeil;
        dst->egressRate = src.egressRate;
        dst->egressCeil = src.egressCeil;
        dst->burst = src.burst;
        dst->vlan = src.vlan;
    }

    bool setQosRule(const QosRule &rule)
    {
        if (!m_initialized) {
            return false;
        }

        // update existing rule
        for (auto it = m_cfg.rules.begin(); it != m_cfg.rules.end(); ++it) {
            if (rule.name == it->name) {
                QosRule *ptr = &(*it);
                updateQosRule(ptr, rule);
                return true;
            }
        }

        // add new rule
        QosRule newRule;
        newRule.name = rule.name;
        updateQosRule(&newRule, rule);

        m_cfg.rules.push_back(newRule);

        return true;
    }

    QosRule* getQosRule(const std::string& name, int* ruleid)
    {
        *ruleid = 0;

        if (!m_initialized) {
            return NULL;
        }

        int id = 1;
        for (auto it = m_cfg.rules.begin(); it != m_cfg.rules.end(); ++it) {
            if (name == it->name) {
                QosRule *ptr = &(*it);
                *ruleid = id;
                return ptr;
            }
            id++;
        }

        return NULL;
    }

    bool delQosRule(const std::string &name)
    {
        if (!m_initialized) {
            return false;
        }

        for (auto it = m_cfg.rules.begin(); it != m_cfg.rules.end(); ++it) {
            if (name == it->name) {
                m_cfg.rules.erase(it);
                return true;
            }
        }

        return true;
    }

    bool getQosConfig(QosConfig *config)
    {
        if (!m_initialized) {
            return false;
        }

        config->enabled = m_cfg.enabled;
        config->rules = m_cfg.rules;

        return true;
    }

    std::string getIngressIfname(const std::string& name)
    {
        if (!m_initialized) {
            return "ifb0";
        }

        std::set<std::string /* label */> lbs;
        int idx = -1;
        for (auto it = m_cfg.rules.begin(); it != m_cfg.rules.end(); ++it) {
            std::string label = it->label;
            if (label.length() && lbs.find(label) == lbs.end()) {
                lbs.insert(label);
                idx++;
            }

            if (name == it->name)
                return "ifb" + std::to_string(idx);
        }

        return "ifb0";
    }

private:
    // Has policy been initialized?
    bool m_initialized;

    // The time level 'config' settings
    QosConfig m_cfg;

    // parsed yml N-ary tree
    GNode *m_yml;

    // Clear out any current configuration
    void clear()
    {
        m_initialized = false;
        m_cfg.enabled = true;
        m_cfg.rules.clear();
    }

    // Method to read the role policy and populate the role member variables
    bool parsePolicy(const char* policyFile)
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

        size_t num = SizeOfYmlSeq(m_yml, "rules");
        for (size_t i = 1 ; i <= num ; i++) {
            QosRule obj;

            HexYmlParseBool(&obj.enabled, m_yml, "rules.%d.enabled", i);
            HexYmlParseInt((int64_t*)&obj.type, 0, QOS_RULE_TYPE_MAX, m_yml, "rules.%d.type", i);
            HexYmlParseString(obj.name, m_yml, "rules.%d.name", i);
            HexYmlParseString(obj.label, m_yml, "rules.%d.label", i);
            HexYmlParseString(obj.ipRange, m_yml, "rules.%d.ip-range", i);
            HexYmlParseUInt(&obj.egressRate, 0, MAX_RATE, m_yml, "rules.%d.egress-rate", i);
            HexYmlParseUInt(&obj.egressCeil, 0, MAX_RATE, m_yml, "rules.%d.egress-ceil", i);
            HexYmlParseUInt(&obj.ingressRate, 0, MAX_RATE, m_yml, "rules.%d.ingress-rate", i);
            HexYmlParseUInt(&obj.ingressCeil, 0, MAX_RATE, m_yml, "rules.%d.ingress-ceil", i);
            HexYmlParseUInt(&obj.burst, 0, MAX_RATE, m_yml, "rules.%d.burst", i);
            HexYmlParseUInt(&obj.vlan, 0, 4095, m_yml, "rules.%d.vlan", i);

            m_cfg.rules.push_back(obj);
        }

        //DumpYmlNode(m_yml);

        return true;
    }
};

#endif /* endif POLICY_QOS_H */

