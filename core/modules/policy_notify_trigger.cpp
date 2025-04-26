// CUBE SDK

#include "include/policy_notify_setting.h"
#include "include/policy_notify_trigger.h"

std::string escapeDoubleQuote(const std::string& str)
{
    // Escape each single quoat(") to '\"'
    std::stringstream out;
    for (std::string::const_iterator it = str.begin(); it != str.end(); it++) {
        if (*it == '"') {
            out << "\\\"";
        } else {
            out << *it;
        }
    }

    return out.str();
}

NotifyTriggerPolicy::NotifyTriggerPolicy():
    isInitialized(false),
    ymlRoot(NULL),
    settingPolicy(nullptr)
{
    this->config.triggers = std::vector<NotifyTrigger>();
}

NotifyTriggerPolicy::~NotifyTriggerPolicy()
{
    if (this->ymlRoot) {
        FiniYml(this->ymlRoot);
        this->ymlRoot = NULL;
    }
    this->settingPolicy = nullptr;
}

const char*
NotifyTriggerPolicy::policyName() const
{
    return "alert_resp";
}

const char*
NotifyTriggerPolicy::policyVersion() const
{
    return "2.0";
}

bool
NotifyTriggerPolicy::isReady() const
{
    return this->isInitialized;
}

const NotifyTriggerConfig
NotifyTriggerPolicy::getConfig() const
{
    return this->config;
}

void
NotifyTriggerPolicy::setSettingPolicy(const NotifySettingPolicy* settingPolicy)
{
    if (settingPolicy && settingPolicy->isReady()) {
        this->settingPolicy = settingPolicy;
    }
}

bool
NotifyTriggerPolicy::load(const char* policyFile)
{
    this->isInitialized = false;
    if (this->ymlRoot) {
        FiniYml(this->ymlRoot);
        this->ymlRoot = NULL;
    }
    this->ymlRoot = InitYml(policyFile);
    if (ReadYml(policyFile, this->ymlRoot) < 0) {
        FiniYml(this->ymlRoot);
        this->ymlRoot = NULL;
        return false;
    }

    std::set<std::string> triggerNameSet;
    std::size_t triggerCount = SizeOfYmlSeq(this->ymlRoot, "triggers");
    for (std::size_t i = 1; i <= triggerCount; i++) {
        NotifyTrigger t;
        HexYmlParseString(t.name, this->ymlRoot, "triggers.%d.name", i);
        if (t.name == "" || triggerNameSet.count(t.name) > 0) {
            // the trigger name should not be blank
            // the trigger name should be unique
            continue;
        }

        HexYmlParseBool(&(t.enabled), this->ymlRoot, "triggers.%d.enabled", i);
        HexYmlParseString(t.topic, this->ymlRoot, "triggers.%d.topic", i);
        HexYmlParseString(t.match, this->ymlRoot, "triggers.%d.match", i);
        HexYmlParseString(t.description, this->ymlRoot, "triggers.%d.description", i);

        // response email
        std::set<std::string> emailAddressSet;
        std::stringstream emailPath;
        emailPath << "triggers." << i << ".responses.emails";
        std::size_t emailCount = SizeOfYmlSeq(this->ymlRoot, emailPath.str().c_str());
        for (std::size_t j = 1; j <= emailCount; j++) {
            NotifyTriggerResponseEmail e;
            HexYmlParseString(e.address, this->ymlRoot, "%s.%zu.address", emailPath.str().c_str(), j);

            if (e.address == "" || emailAddressSet.count(e.address) > 0) {
                // the email address should not be blank
                // the email address should be unique
                continue;
            }

            if (this->settingPolicy && !(this->settingPolicy->hasReceiverEmail(e.address))) {
                // the email address should also be in the setting policy
                continue;
            }

            t.responses.emails.push_back(e);
            emailAddressSet.insert(e.address);
        }

        // response slack
        std::set<std::string> slackUrlSet;
        std::stringstream slackPath;
        slackPath << "triggers." << i << ".responses.slacks";
        std::size_t slackCount = SizeOfYmlSeq(this->ymlRoot, slackPath.str().c_str());
        for (std::size_t j = 1; j <= slackCount; j++) {
            NotifyTriggerResponseSlack s;
            HexYmlParseString(s.url, this->ymlRoot, "%s.%zu.url", slackPath.str().c_str(), j);

            if (s.url == "" || slackUrlSet.count(s.url) > 0) {
                // the slack url should not be blank
                // the slack url should be unique
                continue;
            }

            if (this->settingPolicy && !(this->settingPolicy->hasReceiverSlack(s.url))) {
                // the slack url should also be in the setting policy
                continue;
            }

            t.responses.slacks.push_back(s);
            slackUrlSet.insert(s.url);
        }

        // response exec shell
        std::set<std::string> execShellNameSet;
        std::stringstream execShellPath;
        execShellPath << "triggers." << i << ".responses.execs.shells";
        std::size_t execShellCount = SizeOfYmlSeq(this->ymlRoot, execShellPath.str().c_str());
        for (std::size_t j = 1; j <= execShellCount; j++) {
            NotifyTriggerResponseExecShell es;
            HexYmlParseString(es.name, this->ymlRoot, "%s.%zu.name", execShellPath.str().c_str(), j);

            if (es.name == "" || execShellNameSet.count(es.name) > 0) {
                // the exec shell name should not be blank
                // the exec shell name should be unique
                continue;
            }

            if (this->settingPolicy && !(this->settingPolicy->hasReceiverExecShell(es.name))) {
                // the exec shell name should also be in the setting policy
                continue;
            }

            t.responses.execs.shells.push_back(es);
            execShellNameSet.insert(es.name);
        }

        // response exec bin
        std::set<std::string> execBinNameSet;
        std::stringstream execBinPath;
        execBinPath << "triggers." << i << ".responses.execs.bins";
        std::size_t execBinCount = SizeOfYmlSeq(this->ymlRoot, execBinPath.str().c_str());
        for (std::size_t j = 1; j <= execBinCount; j++) {
            NotifyTriggerResponseExecBin eb;
            HexYmlParseString(eb.name, this->ymlRoot, "%s.%zu.name", execBinPath.str().c_str(), j);

            if (eb.name == "" || execBinNameSet.count(eb.name) > 0) {
                // the exec bin name should not be blank
                // the exec bin name should be unique
                continue;
            }

            if (this->settingPolicy && !(this->settingPolicy->hasReceiverExecBin(eb.name))) {
                // the exec bin name should also be in the setting policy
                continue;
            }

            t.responses.execs.bins.push_back(eb);
            execBinNameSet.insert(eb.name);
        }

        this->config.triggers.push_back(t);
        triggerNameSet.insert(t.name);
    }

    this->isInitialized = true;
    return this->isInitialized;
}

bool
NotifyTriggerPolicy::save(const char* policyFile)
{
    if (DeleteYmlChildren(this->ymlRoot, "triggers") != 0) {
        return false;
    }
    if (this->config.triggers.size() == 0) {
        // the yml parser needs to set at least one blank child
        // we would create a blank child if we do not have any
        NotifyTriggerResponseEmail blankEmail;
        blankEmail.address = "";
        NotifyTriggerResponseSlack blankSlack;
        blankSlack.url = "";
        NotifyTriggerResponseExecShell blankExecShell;
        blankExecShell.name = "";
        NotifyTriggerResponseExecBin blankExecBin;
        blankExecBin.name = "";
        NotifyTrigger blankTrigger;
        blankTrigger.name = "";
        blankTrigger.enabled = false;
        blankTrigger.topic = "";
        blankTrigger.match = "";
        blankTrigger.description = "";
        blankTrigger.responses.emails.push_back(blankEmail);
        blankTrigger.responses.slacks.push_back(blankSlack);
        blankTrigger.responses.execs.shells.push_back(blankExecShell);
        blankTrigger.responses.execs.bins.push_back(blankExecBin);
        this->config.triggers.push_back(blankTrigger);
    }
    for (std::size_t i = 0; i < this->config.triggers.size(); i++) {
        // yml index starts from 1
        std::string ymlIndex = std::to_string(i + 1);
        if (AddYmlKey(this->ymlRoot, "triggers", ymlIndex.c_str()) != 0) {
            return false;
        }
        std::string prefix = std::string("triggers.").append(ymlIndex);

        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "name", this->config.triggers[i].name.c_str()) != 0) {
            return false;
        }
        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "enabled", this->config.triggers[i].enabled ? "true" : "false") != 0) {
            return false;
        }
        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "topic", this->config.triggers[i].topic.c_str()) != 0) {
            return false;
        }
        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "match", (std::string("\"") + escapeDoubleQuote(this->config.triggers[i].match) + std::string("\"")).c_str()) != 0) {
            return false;
        }
        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "description", this->config.triggers[i].description.c_str()) != 0) {
            return false;
        }
        if (AddYmlKey(this->ymlRoot, prefix.c_str(), "responses") != 0) {
            return false;
        }
        std::string responsePath = prefix + std::string(".responses");

        // response email
        if (AddYmlKey(this->ymlRoot, responsePath.c_str(), "emails") != 0) {
            return false;
        }
        std::string emailPath = responsePath + std::string(".emails");
        if (this->config.triggers[i].responses.emails.size() == 0) {
            // the yml parser needs to set at least one blank child
            // we would create a blank child if we do not have any
            NotifyTriggerResponseEmail blankEmail;
            blankEmail.address = "";
            this->config.triggers[i].responses.emails.push_back(blankEmail);
        }
        for (std::size_t j = 0; j < this->config.triggers[i].responses.emails.size(); j++) {
            // yml index starts from 1
            std::string emailYmlIndex = std::to_string(j + 1);
            if (AddYmlKey(this->ymlRoot, emailPath.c_str(), emailYmlIndex.c_str()) != 0) {
                return false;
            }
            std::string emailPrefix = emailPath + std::string(".") + std::string(emailYmlIndex);
            if (AddYmlNode(this->ymlRoot, emailPrefix.c_str(), "address", this->config.triggers[i].responses.emails[j].address.c_str()) != 0) {
                return false;
            }
        }

        // response slack
        if (AddYmlKey(this->ymlRoot, responsePath.c_str(), "slacks") != 0) {
            return false;
        }
        std::string slackPath = responsePath + std::string(".slacks");
        if (this->config.triggers[i].responses.slacks.size() == 0) {
            // the yml parser needs to set at least one blank child
            // we would create a blank child if we do not have any
            NotifyTriggerResponseSlack blankSlack;
            blankSlack.url = "";
            this->config.triggers[i].responses.slacks.push_back(blankSlack);
        }
        for (std::size_t j = 0; j < this->config.triggers[i].responses.slacks.size(); j++) {
            // yml index starts from 1
            std::string slackYmlIndex = std::to_string(j + 1);
            if (AddYmlKey(this->ymlRoot, slackPath.c_str(), slackYmlIndex.c_str()) != 0) {
                return false;
            }
            std::string slackPrefix = slackPath + std::string(".") + std::string(slackYmlIndex);
            if (AddYmlNode(this->ymlRoot, slackPrefix.c_str(), "url", this->config.triggers[i].responses.slacks[j].url.c_str()) != 0) {
                return false;
            }
        }

        // response exec
        if (AddYmlKey(this->ymlRoot, responsePath.c_str(), "execs") != 0) {
            return false;
        }
        std::string execPath = responsePath + std::string(".execs");

        // response exec shell
        if (AddYmlKey(this->ymlRoot, execPath.c_str(), "shells") != 0) {
            return false;
        }
        std::string execShellPath = execPath + std::string(".shells");
        if (this->config.triggers[i].responses.execs.shells.size() == 0) {
            // the yml parser needs to set at least one blank child
            // we would create a blank child if we do not have any
            NotifyTriggerResponseExecShell blankExecShell;
            blankExecShell.name = "";
            this->config.triggers[i].responses.execs.shells.push_back(blankExecShell);
        }
        for (std::size_t j = 0; j < this->config.triggers[i].responses.execs.shells.size(); j++) {
            // yml index starts from 1
            std::string execShellYmlIndex = std::to_string(j + 1);
            if (AddYmlKey(this->ymlRoot, execShellPath.c_str(), execShellYmlIndex.c_str()) != 0) {
                return false;
            }
            std::string execShellPrefix = execShellPath + std::string(".") + std::string(execShellYmlIndex);
            if (AddYmlNode(this->ymlRoot, execShellPrefix.c_str(), "name", this->config.triggers[i].responses.execs.shells[j].name.c_str()) != 0) {
                return false;
            }
        }

        // response exec bin
        if (AddYmlKey(this->ymlRoot, execPath.c_str(), "bins") != 0) {
            return false;
        }
        std::string execBinPath = execPath + std::string(".bins");
        if (this->config.triggers[i].responses.execs.bins.size() == 0) {
            // the yml parser needs to set at least one blank child
            // we would create a blank child if we do not have any
            NotifyTriggerResponseExecBin blankExecBin;
            blankExecBin.name = "";
            this->config.triggers[i].responses.execs.bins.push_back(blankExecBin);
        }
        for (std::size_t j = 0; j < this->config.triggers[i].responses.execs.bins.size(); j++) {
            // yml index starts from 1
            std::string execBinYmlIndex = std::to_string(j + 1);
            if (AddYmlKey(this->ymlRoot, execBinPath.c_str(), execBinYmlIndex.c_str()) != 0) {
                return false;
            }
            std::string execBinPrefix = execBinPath + std::string(".") + std::string(execBinYmlIndex);
            if (AddYmlNode(this->ymlRoot, execBinPrefix.c_str(), "name", this->config.triggers[i].responses.execs.bins[j].name.c_str()) != 0) {
                return false;
            }
        }
    }

    return (WriteYml(policyFile, this->ymlRoot) == 0);
}

void
NotifyTriggerPolicy::addOrUpdateTrigger(
    std::string name,
    bool enabled,
    std::string topic,
    std::string match,
    std::string description,
    const std::vector<std::string>& emails,
    const std::vector<std::string>& slacks,
    const std::vector<std::string>& execShells,
    const std::vector<std::string>& execBins
)
{
    if (!this->isInitialized) {
        return;
    }

    // check if the trigger exists or not
    std::vector<NotifyTrigger>* triggers = &(this->config.triggers);
    if (triggers == nullptr) {
        return;
    }
    NotifyTrigger* t = nullptr;
    for (std::vector<NotifyTrigger>::iterator it = triggers->begin(); it != triggers->end(); it++) {
        if (it->name == name) {
            t = &(*it);
        }
    }

    // add or update
    if (t == nullptr) {
        // add
        NotifyTrigger newTrigger;
        newTrigger.name = name;
        newTrigger.enabled = enabled;
        newTrigger.topic = topic;
        newTrigger.match = match;
        newTrigger.description = description;
        // email
        for (std::vector<std::string>::const_iterator it = emails.begin(); it != emails.end(); it++) {
            if (this->settingPolicy && !(this->settingPolicy->hasReceiverEmail(*it))) {
                // the email address should also be in the setting policy
                continue;
            }

            NotifyTriggerResponseEmail newEmail;
            newEmail.address = *it;
            newTrigger.responses.emails.push_back(newEmail);
        }
        // slack
        for (std::vector<std::string>::const_iterator it = slacks.begin(); it != slacks.end(); it++) {
            if (this->settingPolicy && !(this->settingPolicy->hasReceiverSlack(*it))) {
                // the slack url should also be in the setting policy
                continue;
            }

            NotifyTriggerResponseSlack newSlack;
            newSlack.url = *it;
            newTrigger.responses.slacks.push_back(newSlack);
        }
        // exec shell
        for (std::vector<std::string>::const_iterator it = execShells.begin(); it != execShells.end(); it++) {
            if (this->settingPolicy && !(this->settingPolicy->hasReceiverExecShell(*it))) {
                // the exec shell name should also be in the setting policy
                continue;
            }

            NotifyTriggerResponseExecShell newExecShell;
            newExecShell.name = *it;
            newTrigger.responses.execs.shells.push_back(newExecShell);
        }
        // exec bin
        for (std::vector<std::string>::const_iterator it = execBins.begin(); it != execBins.end(); it++) {
            if (this->settingPolicy && !(this->settingPolicy->hasReceiverExecBin(*it))) {
                // the exec bin name should also be in the setting policy
                continue;
            }

            NotifyTriggerResponseExecBin newExecBin;
            newExecBin.name = *it;
            newTrigger.responses.execs.bins.push_back(newExecBin);
        }
        this->config.triggers.push_back(newTrigger);
    } else {
        // update
        t->name = name;
        t->enabled = enabled;
        t->topic = topic;
        t->match = match;
        t->description = description;
        // email
        t->responses.emails.clear();
        for (std::vector<std::string>::const_iterator it = emails.begin(); it != emails.end(); it++) {
            if (this->settingPolicy && !(this->settingPolicy->hasReceiverEmail(*it))) {
                // the email address should also be in the setting policy
                continue;
            }

            NotifyTriggerResponseEmail newEmail;
            newEmail.address = *it;
            t->responses.emails.push_back(newEmail);
        }
        // slack
        t->responses.slacks.clear();
        for (std::vector<std::string>::const_iterator it = slacks.begin(); it != slacks.end(); it++) {
            if (this->settingPolicy && !(this->settingPolicy->hasReceiverSlack(*it))) {
                // the slack url should also be in the setting policy
                continue;
            }

            NotifyTriggerResponseSlack newSlack;
            newSlack.url = *it;
            t->responses.slacks.push_back(newSlack);
        }
        // exec shell
        t->responses.execs.shells.clear();
        for (std::vector<std::string>::const_iterator it = execShells.begin(); it != execShells.end(); it++) {
            if (this->settingPolicy && !(this->settingPolicy->hasReceiverExecShell(*it))) {
                // the exec shell name should also be in the setting policy
                continue;
            }

            NotifyTriggerResponseExecShell newExecShell;
            newExecShell.name = *it;
            t->responses.execs.shells.push_back(newExecShell);
        }
        // exec bin
        t->responses.execs.bins.clear();
        for (std::vector<std::string>::const_iterator it = execBins.begin(); it != execBins.end(); it++) {
            if (this->settingPolicy && !(this->settingPolicy->hasReceiverExecBin(*it))) {
                // the exec bin name should also be in the setting policy
                continue;
            }

            NotifyTriggerResponseExecBin newExecBin;
            newExecBin.name = *it;
            t->responses.execs.bins.push_back(newExecBin);
        }
    }
}

bool
NotifyTriggerPolicy::deleteTrigger(std::string name)
{
    if (!this->isInitialized) {
        return false;
    }

    bool isSuccessful = false;

    std::vector<NotifyTrigger>* triggers = &(this->config.triggers);
    if (triggers == nullptr) {
        return isSuccessful;
    }

    for (std::vector<NotifyTrigger>::iterator it = triggers->begin(); it != triggers->end();) {
        if (it->name == name) {
            it = triggers->erase(it);
            isSuccessful = true;
        } else {
            it++;
        }
    }

    return isSuccessful;
}

void
NotifyTriggerPolicy::deleteEmail(std::string address)
{
    if (!this->isInitialized) {
        return;
    }

    for (std::vector<NotifyTrigger>::iterator it = this->config.triggers.begin(); it != this->config.triggers.end(); it++) {
        for (std::vector<NotifyTriggerResponseEmail>::iterator jt = it->responses.emails.begin(); jt != it->responses.emails.end();) {
            if (jt->address == address) {
                jt = it->responses.emails.erase(jt);
            } else {
                jt++;
            }
        }
    }
}

void
NotifyTriggerPolicy::deleteSlack(std::string url)
{
    if (!this->isInitialized) {
        return;
    }

    for (std::vector<NotifyTrigger>::iterator it = this->config.triggers.begin(); it != this->config.triggers.end(); it++) {
        for (std::vector<NotifyTriggerResponseSlack>::iterator jt = it->responses.slacks.begin(); jt != it->responses.slacks.end();) {
            if (jt->url == url) {
                jt = it->responses.slacks.erase(jt);
            } else {
                jt++;
            }
        }
    }
}

void
NotifyTriggerPolicy::deleteExecShell(std::string name)
{
    if (!this->isInitialized) {
        return;
    }

    for (std::vector<NotifyTrigger>::iterator it = this->config.triggers.begin(); it != this->config.triggers.end(); it++) {
        for (std::vector<NotifyTriggerResponseExecShell>::iterator jt = it->responses.execs.shells.begin(); jt != it->responses.execs.shells.end();) {
            if (jt->name == name) {
                jt = it->responses.execs.shells.erase(jt);
            } else {
                jt++;
            }
        }
    }
}

void
NotifyTriggerPolicy::deleteExecBin(std::string name)
{
    if (!this->isInitialized) {
        return;
    }

    for (std::vector<NotifyTrigger>::iterator it = this->config.triggers.begin(); it != this->config.triggers.end(); it++) {
        for (std::vector<NotifyTriggerResponseExecBin>::iterator jt = it->responses.execs.bins.begin(); jt != it->responses.execs.bins.end();) {
            if (jt->name == name) {
                jt = it->responses.execs.bins.erase(jt);
            } else {
                jt++;
            }
        }
    }
}
