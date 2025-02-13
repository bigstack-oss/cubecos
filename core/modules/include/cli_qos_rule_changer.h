// HEX SDK

#ifndef CLI_QOS_RULE_CHANGER_H
#define CLI_QOS_RULE_CHANGER_H

#include <sys/socket.h>

#define MAX_RATE 100000000L // 100Gbps

static const char* LABEL_RULE_CONFIG_ACTION = "Select action: ";
static const char* LABEL_RULE_CONFIG_ID = "Select rule ID: ";
static const char* LABEL_RULE_CONFIG_NAME = "Enter rule name (required): ";
static const char* LABEL_RULE_CONFIG_IF = "Enter network interface (required): ";
static const char* LABEL_RULE_CONFIG_TYPE = "Select rule type: ";
static const char* LABEL_RULE_EGRESS_RATE = "Enter egress rate in kbps [%lu-%lu]: ";
static const char* LABEL_RULE_EGRESS_CEIL = "Enter egress ceil in kbps [%lu-%lu]: ";
static const char* LABEL_RULE_INGRESS_RATE = "Enter ingress rate in kbps [%lu-%lu]: ";
static const char* LABEL_RULE_INGRESS_CEIL = "Enter ingress ceil in kbps [%lu-%lu]: ";
static const char* LABEL_RULE_VLAN = "Enter vlan ID [0-4095]: ";
static const char* LABEL_RULE_IP_RANGE = "Enter IP range [IP,IP-IP,...]: ";

class CliQosRuleChanger
{
public:
    bool configure(QosPolicy *policy)
    {
        return construct(policy);
    }

    bool getRuleName(const QosConfig &cfg, std::string* name)
    {
        CliPrint(LABEL_RULE_CONFIG_ID);
        CliList ruleList;
        std::vector<std::string> namelist;

        int idx = 0;
        namelist.resize(cfg.rules.size());
        for (auto it = cfg.rules.begin(); it != cfg.rules.end(); ++it) {
            ruleList.push_back(it->name);
            namelist[idx++] = it->name;
        }

        idx = CliReadListIndex(ruleList);
        if (idx < 0) {
            return false;
        }

        *name = namelist[idx];
        return true;
    }

private:
    enum {
        ACTION_ADD = 0,
        ACTION_DELETE,
        ACTION_UPDATE
    };

    bool getAction(int *action)
    {
        CliPrint(LABEL_RULE_CONFIG_ACTION);
        CliList actList;
        actList.push_back("Add");
        actList.push_back("Delete");
        actList.push_back("Update");
        int idx = CliReadListIndex(actList);
        if (idx < 0) {
            return false;
        }

        *action = idx;
        return true;
    }

    bool setRuleName(std::string* name)
    {
        if (!CliReadLine(LABEL_RULE_CONFIG_NAME, *name)) {
            return false;
        }

        if (!name->length()) {
            CliPrint("Rule name is required\n");
            return false;
        }

        return true;
    }

    bool setRuleType(int *type)
    {
        CliPrint(LABEL_RULE_CONFIG_TYPE);
        CliList actList;
        actList.push_back("Shared");
        actList.push_back("Per IP Address");
        int idx = CliReadListIndex(actList);
        if (idx < 0 || idx > QOS_RULE_TYPE_MAX) {
            return false;
        }

        *type = idx;
        return true;
    }

    bool setRuleLabel(std::string* label)
    {
        if (!CliReadLine(LABEL_RULE_CONFIG_IF, *label)) {
            return false;
        }

        if (!label->length() || label->length() > 16) {
            CliPrintf("Invalid interface name %s\n", label->c_str());
            return false;
        }

        return true;
    }

    bool setRuleRate(uint64_t* erate, uint64_t* eceil, uint64_t* irate, uint64_t* iceil)
    {
        std::string strERate, strECeil, strIRate, strICeil;

        char msg[256];

        snprintf(msg, sizeof(msg), LABEL_RULE_EGRESS_RATE, 0, MAX_RATE);
        if (!CliReadLine(msg, strERate)) {
            return false;
        }

        if (!HexValidateUInt(strERate.c_str(), 0, MAX_RATE)) {
            CliPrintf("Invalid rate number %s\n", strERate.c_str());
            return false;
        }

        *erate = std::stoul(strERate);

        snprintf(msg, sizeof(msg), LABEL_RULE_EGRESS_CEIL, *erate, MAX_RATE);
        if (!CliReadLine(msg, strECeil)) {
            return false;
        }

        if (!HexValidateUInt(strECeil.c_str(), *erate, MAX_RATE)) {
            CliPrintf("Invalid ceil number %s\n", strECeil.c_str());
            return false;
        }

        *eceil = std::stoul(strECeil);

        snprintf(msg, sizeof(msg), LABEL_RULE_INGRESS_RATE, 0, MAX_RATE);
        if (!CliReadLine(msg, strIRate)) {
            return false;
        }

        if (!HexValidateUInt(strIRate.c_str(), 0, MAX_RATE)) {
            CliPrintf("Invalid rate number %s\n", strIRate.c_str());
            return false;
        }

        *irate = std::stoul(strIRate);

        snprintf(msg, sizeof(msg), LABEL_RULE_INGRESS_CEIL, *irate, MAX_RATE);
        if (!CliReadLine(msg, strICeil)) {
            return false;
        }

        if (!HexValidateUInt(strICeil.c_str(), *irate, MAX_RATE)) {
            CliPrintf("Invalid ceil number %s\n", strICeil.c_str());
            return false;
        }

        *iceil = std::stoul(strICeil);

        return true;
    }

    bool setRuleVlan(uint64_t* vlan)
    {
        std::string strVlan;
        if (!CliReadLine(LABEL_RULE_VLAN, strVlan)) {
            return false;
        }

        if (strVlan.length() == 0) {
            *vlan = 0;
            return true;
        }

        if (!HexValidateUInt(strVlan.c_str(), 0, 4096)) {
            CliPrintf("Invalid vlan number %s\n", strVlan.c_str());
            return false;
        }

        *vlan = std::stoul(strVlan);

        return true;
    }

    bool setRuleIpRange(std::string* ipRange)
    {
        std::string strIpr;
        if (!CliReadLine(LABEL_RULE_IP_RANGE, strIpr)) {
            return false;
        }

        if (strIpr.length() == 0) {
            *ipRange = "";
            return true;
        }

        if (!HexParseIPList(strIpr.c_str(), AF_INET)) {
            CliPrintf("Invalid IP range %s\n", strIpr.c_str());
            return false;
        }

        *ipRange = strIpr;

        return true;
    }

    bool construct(QosPolicy *policy)
    {
        int action = ACTION_ADD;
        if (!getAction(&action)) {
            return false;
        }

        QosConfig cfg;
        policy->getQosConfig(&cfg);
        QosRule rule;

        if (action == ACTION_DELETE || action == ACTION_UPDATE) {
            if (!getRuleName(cfg, &rule.name)) {
                return false;
            }
        }
        else if (action == ACTION_ADD) {
            if (!setRuleName(&rule.name)) {
                return false;
            }
        }

        switch (action) {
            case ACTION_DELETE:
                if (!policy->delQosRule(rule.name)) {
                    HexLogError("failed to delete QoS rule: %s", rule.name.c_str());
                    return false;
                }
                break;
            case ACTION_ADD:
            case ACTION_UPDATE:
                if (!setRuleLabel(&rule.label)) {
                    return false;
                }

                if (!setRuleRate(&rule.egressRate, &rule.egressCeil, &rule.ingressRate, &rule.ingressCeil)) {
                    return false;
                }

                if (!setRuleVlan(&rule.vlan)) {
                    return false;
                }

                if (!setRuleIpRange(&rule.ipRange)) {
                    return false;
                }

                if (rule.ipRange.length() && !setRuleType(&rule.type)) {
                    return false;
                }

                CliPrintf("\n%s rule: %s", action == ACTION_ADD ? "Adding" : "Updating", rule.name.c_str());
                if (rule.ipRange.length())
                    CliPrintf("type: %s", rule.type == QOS_RULE_PER_IP ? "Per IP Address" : "Shared");
                CliPrintf("network interface: %s", rule.label.c_str());
                CliPrintf("egress rate: %lukbps", rule.egressRate);
                CliPrintf("egress ceil: %lukbps", rule.egressCeil);
                CliPrintf("ingress rate: %lukbps", rule.ingressRate);
                CliPrintf("ingress ceil: %lukbps", rule.ingressCeil);
                if (rule.vlan)
                    CliPrintf("vlan: %lu", rule.vlan);
                if (rule.ipRange.length())
                    CliPrintf("ip range: %s", rule.ipRange.c_str());

                CliReadContinue();
                policy->setQosRule(rule);
                break;
        }

        return true;
    }
};

#endif /* endif CLI_QOS_RULE_CHANGER_H */

