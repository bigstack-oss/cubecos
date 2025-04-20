// CUBE SDK

#include "include/policy_notify_setting.h"
#include "include/policy_notify_trigger.h"

NotifySettingPolicy::NotifySettingPolicy():
    isInitialized(false),
    ymlRoot(NULL),
    triggerPolicy(nullptr)
{
    this->config.titlePrefix = "";

    NotifySettingSenderEmail se;
    se.host = "";
    se.port = "";
    se.username = "";
    se.password = "";
    se.from = "";
    NotifySettingSender s;
    s.email = se;
    this->config.sender = s;

    NotifySettingReceiverExec re;
    re.shells = std::vector<NotifySettingReceiverExecShell>();
    re.bins = std::vector<NotifySettingReceiverExecBin>();
    NotifySettingReceiver r;
    r.emails = std::vector<NotifySettingReceiverEmail>();
    r.slacks = std::vector<NotifySettingReceiverSlack>();
    r.execs = re;
    this->config.receiver = r;
}

NotifySettingPolicy::~NotifySettingPolicy()
{
    if (this->ymlRoot) {
        FiniYml(this->ymlRoot);
        this->ymlRoot = NULL;
    }
    this->triggerPolicy = nullptr;
}

const char*
NotifySettingPolicy::policyName() const
{
    return "alert_setting";
}

const char*
NotifySettingPolicy::policyVersion() const
{
    return "1.0";
}

bool
NotifySettingPolicy::isReady() const
{
    return this->isInitialized;
}

const NotifySettingConfig
NotifySettingPolicy::getConfig() const
{
    return this->config;
}

void
NotifySettingPolicy::setTriggerPolicy(NotifyTriggerPolicy* triggerPolicy)
{
    if (triggerPolicy->isReady()) {
        this->triggerPolicy = triggerPolicy;
    }
}

bool
NotifySettingPolicy::load(const char* policyFile)
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

    // title prefix
    HexYmlParseString(this->config.titlePrefix, this->ymlRoot, "titlePrefix");

    // sender email
    HexYmlParseString(this->config.sender.email.host, this->ymlRoot, "sender.email.host");
    HexYmlParseString(this->config.sender.email.port, this->ymlRoot, "sender.email.port");
    HexYmlParseString(this->config.sender.email.username, this->ymlRoot, "sender.email.username");
    HexYmlParseString(this->config.sender.email.password, this->ymlRoot, "sender.email.password");
    HexYmlParseString(this->config.sender.email.from, this->ymlRoot, "sender.email.from");

    if ((
        this->config.sender.email.host != "" ||
        this->config.sender.email.port != "" ||
        this->config.sender.email.username != "" ||
        this->config.sender.email.password != "" ||
        this->config.sender.email.from != ""
    ) && (
        this->config.sender.email.host == "" ||
        this->config.sender.email.port == "" ||
        this->config.sender.email.from == ""
    )) {
        // we only allow username and password to be blank
        // otherwise, reset the values
        this->config.sender.email.host = "";
        this->config.sender.email.port = "";
        this->config.sender.email.username = "";
        this->config.sender.email.password = "";
        this->config.sender.email.from = "";
    }

    // receiver email
    std::set<std::string> receiverEmailAddressSet;
    std::size_t receiverEmailCount = SizeOfYmlSeq(this->ymlRoot, "receiver.emails");
    for (std::size_t i = 1; i <= receiverEmailCount; i++) {
        NotifySettingReceiverEmail e;
        HexYmlParseString(e.address, this->ymlRoot, "receiver.emails.%zu.address", i);

        if (e.address == "") {
            // we do not allow receiver email with a blank address
            // since this field is used as an id for the receiver email
            continue;
        }

        if (receiverEmailAddressSet.count(e.address) > 0) {
            // receiver email address should be unique
            // since it is an id
            continue;
        }

        HexYmlParseString(e.note, this->ymlRoot, "receiver.emails.%zu.note", i);

        this->config.receiver.emails.push_back(e);
        receiverEmailAddressSet.insert(e.address);
    }

    // receiver slack
    std::set<std::string> receiverSlackUrlSet;
    std::size_t receiverSlackCount = SizeOfYmlSeq(this->ymlRoot, "receiver.slacks");
    for (std::size_t i = 1; i <= receiverSlackCount; i++) {
        NotifySettingReceiverSlack s;
        HexYmlParseString(s.url, this->ymlRoot, "receiver.slacks.%zu.url", i);

        if (s.url == "") {
            // we do not allow receiver slack with a blank url
            // since this field is used as an id for the receiver slack
            continue;
        }

        if (receiverSlackUrlSet.count(s.url) > 0) {
            // receiver slack url should be unique
            // since it is an id
            continue;
        }

        HexYmlParseString(s.username, this->ymlRoot, "receiver.slacks.%zu.username", i);
        HexYmlParseString(s.description, this->ymlRoot, "receiver.slacks.%zu.description", i);
        HexYmlParseString(s.workspace, this->ymlRoot, "receiver.slacks.%zu.workspace", i);
        HexYmlParseString(s.channel, this->ymlRoot, "receiver.slacks.%zu.channel", i);

        this->config.receiver.slacks.push_back(s);
        receiverSlackUrlSet.insert(s.url);
    }

    // receiver exec shell
    std::set<std::string> receiverExecShellNameSet;
    std::size_t receiverExecShellCount = SizeOfYmlSeq(this->ymlRoot, "receiver.execs.shells");
    for (std::size_t i = 1; i <= receiverExecShellCount; i++) {
        NotifySettingReceiverExecShell es;
        HexYmlParseString(es.name, this->ymlRoot, "receiver.execs.shells.%zu.name", i);

        if (es.name == "") {
            // we do not allow receiver exec shell with a blank name
            // since this field is used as an id for the receiver exec shell
            continue;
        }

        if (receiverExecShellNameSet.count(es.name) > 0) {
            // receiver exec shell name should be unique
            // since it is an id
            continue;
        }

        this->config.receiver.execs.shells.push_back(es);
        receiverExecShellNameSet.insert(es.name);
    }

    // receiver exec bin
    std::set<std::string> receiverExecBinNameSet;
    std::size_t receiverExecBinCount = SizeOfYmlSeq(this->ymlRoot, "receiver.execs.bins");
    for (std::size_t i = 1; i <= receiverExecBinCount; i++) {
        NotifySettingReceiverExecBin eb;
        HexYmlParseString(eb.name, this->ymlRoot, "receiver.execs.bins.%zu.name", i);

        if (eb.name == "") {
            // we do not allow receiver exec bin with a blank name
            // since this field is used as an id for the receiver exec bin
            continue;
        }

        if (receiverExecBinNameSet.count(eb.name) > 0) {
            // receiver exec bin name should be unique
            // since it is an id
            continue;
        }

        this->config.receiver.execs.bins.push_back(eb);
        receiverExecBinNameSet.insert(eb.name);
    }

    this->isInitialized = true;
    return this->isInitialized;
}

bool
NotifySettingPolicy::save(const char* policyFile)
{
    // title prefix
    if (UpdateYmlValue(this->ymlRoot, "titlePrefix", this->config.titlePrefix.c_str()) != 0) {
        return false;
    }

    // sender email
    if (UpdateYmlValue(this->ymlRoot, "sender.email.host", this->config.sender.email.host.c_str()) != 0) {
        return false;
    }
    if (UpdateYmlValue(this->ymlRoot, "sender.email.port", this->config.sender.email.port.c_str()) != 0) {
        return false;
    }
    if (UpdateYmlValue(this->ymlRoot, "sender.email.username", this->config.sender.email.username.c_str()) != 0) {
        return false;
    }
    if (UpdateYmlValue(this->ymlRoot, "sender.email.password", this->config.sender.email.password.c_str()) != 0) {
        return false;
    }
    if (UpdateYmlValue(this->ymlRoot, "sender.email.from", this->config.sender.email.from.c_str()) != 0) {
        return false;
    }

    // receiver email
    if (DeleteYmlChildren(this->ymlRoot, "receiver.emails") != 0) {
        return false;
    }
    if (this->config.receiver.emails.size() == 0) {
        // the yml parser needs to set at least one blank child
        // we would create a blank child if we do not have any
        NotifySettingReceiverEmail blankReceiverEmail;
        blankReceiverEmail.address = "";
        blankReceiverEmail.note = "";
        this->config.receiver.emails.push_back(blankReceiverEmail);
    }
    for (std::size_t i = 0; i < this->config.receiver.emails.size(); i++) {
        // yml index starts from 1
        std::string ymlIndex = std::to_string(i + 1);
        if (AddYmlKey(this->ymlRoot, "receiver.emails", ymlIndex.c_str()) != 0) {
            return false;
        }
        std::string prefix = std::string("receiver.emails.").append(ymlIndex);
        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "address", this->config.receiver.emails[i].address.c_str()) != 0) {
            return false;
        }
        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "note", this->config.receiver.emails[i].note.c_str()) != 0) {
            return false;
        }
    }

    // receiver slack
    if (DeleteYmlChildren(this->ymlRoot, "receiver.slacks") != 0) {
        return false;
    }
    if (this->config.receiver.slacks.size() == 0) {
        // the yml parser needs to set at least one blank child
        // we would create a blank child if we do not have any
        NotifySettingReceiverSlack blankReceiverSlack;
        blankReceiverSlack.url = "";
        blankReceiverSlack.username = "";
        blankReceiverSlack.description = "";
        blankReceiverSlack.workspace = "";
        blankReceiverSlack.channel = "";
        this->config.receiver.slacks.push_back(blankReceiverSlack);
    }
    for (std::size_t i = 0; i < this->config.receiver.slacks.size(); i++) {
        // yml index starts from 1
        std::string ymlIndex = std::to_string(i + 1);
        if (AddYmlKey(this->ymlRoot, "receiver.slacks", ymlIndex.c_str()) != 0) {
            return false;
        }
        std::string prefix = std::string("receiver.slacks.").append(ymlIndex);
        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "url", this->config.receiver.slacks[i].url.c_str()) != 0) {
            return false;
        }
        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "username", this->config.receiver.slacks[i].username.c_str()) !=0 ) {
            return false;
        }
        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "description", this->config.receiver.slacks[i].description.c_str()) !=0) {
            return false;
        }
        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "workspace", this->config.receiver.slacks[i].workspace.c_str()) != 0) {
            return false;
        }
        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "channel", this->config.receiver.slacks[i].channel.c_str()) != 0) {
            return false;
        }
    }

    // receiver exec shell
    if (DeleteYmlChildren(this->ymlRoot, "receiver.execs.shells") != 0) {
        return false;
    }
    if (this->config.receiver.execs.shells.size() == 0) {
        // the yml parser needs to set at least one blank child
        // we would create a blank child if we do not have any
        NotifySettingReceiverExecShell blankReceiverExecShell;
        blankReceiverExecShell.name = "";
        this->config.receiver.execs.shells.push_back(blankReceiverExecShell);
    }
    for (std::size_t i = 0; i < this->config.receiver.execs.shells.size(); i++) {
        // yml index starts from 1
        std::string ymlIndex = std::to_string(i + 1);
        if (AddYmlKey(this->ymlRoot, "receiver.execs.shells", ymlIndex.c_str()) != 0) {
            return false;
        }
        std::string prefix = std::string("receiver.execs.shells.").append(ymlIndex);
        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "name", this->config.receiver.execs.shells[i].name.c_str()) != 0) {
            return false;
        }
    }

    // receiver exec bin
    if (DeleteYmlChildren(this->ymlRoot, "receiver.execs.bins") != 0) {
        return false;
    }
    if (this->config.receiver.execs.bins.size() == 0) {
        // the yml parser needs to set at least one blank child
        // we would create a blank child if we do not have any
        NotifySettingReceiverExecBin blankReceiverExecBin;
        blankReceiverExecBin.name = "";
        this->config.receiver.execs.bins.push_back(blankReceiverExecBin);
    }
    for (std::size_t i = 0; i < this->config.receiver.execs.bins.size(); i++) {
        // yml index starts from 1
        std::string ymlIndex = std::to_string(i + 1);
        if (AddYmlKey(this->ymlRoot, "receiver.execs.bins", ymlIndex.c_str()) != 0) {
            return false;
        }
        std::string prefix = std::string("receiver.execs.bins.").append(ymlIndex);
        if (AddYmlNode(this->ymlRoot, prefix.c_str(), "name", this->config.receiver.execs.bins[i].name.c_str()) != 0) {
            return false;
        }
    }

    return (WriteYml(policyFile, this->ymlRoot) == 0);
}

bool
NotifySettingPolicy::hasReceiverEmail(std::string address) const
{
    const std::vector<NotifySettingReceiverEmail>* emails = &(this->config.receiver.emails);
    if (emails == nullptr) {
        return false;
    }

    for (std::vector<NotifySettingReceiverEmail>::const_iterator it = emails->begin(); it != emails->end(); it++) {
        if (it->address == address) {
            return true;
        }
    }

    return false;
}

bool
NotifySettingPolicy::hasReceiverSlack(std::string url) const
{
    const std::vector<NotifySettingReceiverSlack>* slacks = &(this->config.receiver.slacks);
    if (slacks == nullptr) {
        return false;
    }

    for (std::vector<NotifySettingReceiverSlack>::const_iterator it = slacks->begin(); it != slacks->end(); it++) {
        if (it->url == url) {
            return true;
        }
    }

    return false;
}

bool
NotifySettingPolicy::hasReceiverExecShell(std::string name) const
{
    const std::vector<NotifySettingReceiverExecShell>* shells = &(this->config.receiver.execs.shells);
    if (shells == nullptr) {
        return false;
    }

    for (std::vector<NotifySettingReceiverExecShell>::const_iterator it = shells->begin(); it != shells->end(); it++) {
        if (it->name == name) {
            return true;
        }
    }

    return false;
}

bool
NotifySettingPolicy::hasReceiverExecBin(std::string name) const
{
    const std::vector<NotifySettingReceiverExecBin>* bins = &(this->config.receiver.execs.bins);
    if (bins == nullptr) {
        return false;
    }

    for (std::vector<NotifySettingReceiverExecBin>::const_iterator it = bins->begin(); it != bins->end(); it++) {
        if (it->name == name) {
            return true;
        }
    }

    return false;
}

void
NotifySettingPolicy::updateSenderEmail(
    std::string host,
    std::string port,
    std::string username,
    std::string password,
    std::string from
)
{
    NotifySettingSenderEmail* email = &(this->config.sender.email);
    if (email == nullptr) {
        return;
    }

    email->host = host;
    email->port = port;
    email->username = username;
    email->password = password;
    email->from = from;
}

void
NotifySettingPolicy::addOrUpdateReceiverEmail(std::string address, std::string note)
{
    // check if the email receiver exists or not
    std::vector<NotifySettingReceiverEmail>* emails = &(this->config.receiver.emails);
    if (emails == nullptr) {
        return;
    }
    NotifySettingReceiverEmail* e = nullptr;
    for (std::vector<NotifySettingReceiverEmail>::iterator it = emails->begin(); it != emails->end(); it++) {
        if (it->address == address) {
            e = &(*it);
        }
    }

    // add or update
    if (e == nullptr) {
        // add
        NotifySettingReceiverEmail newEmail;
        newEmail.address = address;
        newEmail.note = note;
        emails->push_back(newEmail);
    } else {
        // update
        e->address = address;
        e->note = note;
    }
}

void
NotifySettingPolicy::addOrUpdateReceiverSlack(
    std::string url,
    std::string username,
    std::string description,
    std::string workspace,
    std::string channel
)
{
    // check if the slack receiver exists or not
    std::vector<NotifySettingReceiverSlack>* slacks = &(this->config.receiver.slacks);
    if (slacks == nullptr) {
        return;
    }
    NotifySettingReceiverSlack* s = nullptr;
    for (std::vector<NotifySettingReceiverSlack>::iterator it = slacks->begin(); it != slacks->end(); it++) {
        if (it->url == url) {
            s = &(*it);
        }
    }

    // add or update
    if (s == nullptr) {
        // add
        NotifySettingReceiverSlack newSlack;
        newSlack.url = url;
        newSlack.username = username;
        newSlack.description = description;
        newSlack.workspace = workspace;
        newSlack.channel = channel;
        slacks->push_back(newSlack);
    } else {
        // update
        s->url = url;
        s->username = username;
        s->description = description;
        s->workspace = workspace;
        s->channel = channel;
    }
}

void
NotifySettingPolicy::addReceiverExecShell(std::string name)
{
    // check if the email receiver exists or not
    std::vector<NotifySettingReceiverExecShell>* shells = &(this->config.receiver.execs.shells);
    if (shells == nullptr) {
        return;
    }
    NotifySettingReceiverExecShell* es = nullptr;
    for (std::vector<NotifySettingReceiverExecShell>::iterator it = shells->begin(); it != shells->end(); it++) {
        if (it->name == name) {
            es = &(*it);
        }
    }

    // add
    if (es == nullptr) {
        NotifySettingReceiverExecShell newShell;
        newShell.name = name;
        shells->push_back(newShell);
    }
}

void
NotifySettingPolicy::addReceiverExecBin(std::string name)
{
    // check if the email receiver exists or not
    std::vector<NotifySettingReceiverExecBin>* bins = &(this->config.receiver.execs.bins);
    if (bins == nullptr) {
        return;
    }
    NotifySettingReceiverExecBin* eb = nullptr;
    for (std::vector<NotifySettingReceiverExecBin>::iterator it = bins->begin(); it != bins->end(); it++) {
        if (it->name == name) {
            eb = &(*it);
        }
    }

    // add
    if (eb == nullptr) {
        NotifySettingReceiverExecBin newBin;
        newBin.name = name;
        bins->push_back(newBin);
    }
}

void
NotifySettingPolicy::deleteSenderEmail()
{
    NotifySettingSenderEmail* email = &(this->config.sender.email);
    if (email == nullptr) {
        return;
    }

    email->host = "";
    email->port = "";
    email->username = "";
    email->password = "";
    email->from = "";
}

bool
NotifySettingPolicy::deleteReceiverEmail(std::string address)
{
    bool isSuccessful = false;

    std::vector<NotifySettingReceiverEmail>* emails = &(this->config.receiver.emails);
    if (emails == nullptr) {
        return isSuccessful;
    }

    for (std::vector<NotifySettingReceiverEmail>::iterator it = emails->begin(); it != emails->end();) {
        if (it->address == address) {
            it = emails->erase(it);
            isSuccessful = true;
        } else {
            it++;
        }
    }

    // delete on cascade for emails in trigger config
    if (isSuccessful && this->triggerPolicy) {
        this->triggerPolicy->deleteEmail(address);
    }

    return isSuccessful;
}

bool
NotifySettingPolicy::deleteReceiverSlack(std::string url)
{
    bool isSuccessful = false;
    
    std::vector<NotifySettingReceiverSlack>* slacks = &(this->config.receiver.slacks);
    if (slacks == nullptr) {
        return isSuccessful;
    }

    for (std::vector<NotifySettingReceiverSlack>::iterator it = slacks->begin(); it != slacks->end();) {
        if (it->url == url) {
            it = slacks->erase(it);
            isSuccessful = true;
        } else {
            it++;
        }
    }

    // delete on cascade for slacks in trigger config
    if (isSuccessful && this->triggerPolicy) {
        this->triggerPolicy->deleteSlack(url);
    }

    return isSuccessful;
}

bool
NotifySettingPolicy::deleteReceiverExecShell(std::string name)
{
    bool isSuccessful = false;

    std::vector<NotifySettingReceiverExecShell>* shells = &(this->config.receiver.execs.shells);
    if (shells == nullptr) {
        return isSuccessful;
    }

    for (std::vector<NotifySettingReceiverExecShell>::iterator it = shells->begin(); it != shells->end();) {
        if (it->name == name) {
            it = shells->erase(it);
            isSuccessful = true;
        } else {
            it++;
        }
    }

    // delete on cascade for exec shells in trigger config
    if (isSuccessful && this->triggerPolicy) {
        this->triggerPolicy->deleteExecShell(name);
    }

    return isSuccessful;
}

bool
NotifySettingPolicy::deleteReceiverExecBin(std::string name)
{
    bool isSuccessful = false;

    std::vector<NotifySettingReceiverExecBin>* bins = &(this->config.receiver.execs.bins);
    if (bins == nullptr) {
        return isSuccessful;
    }

    for (std::vector<NotifySettingReceiverExecBin>::iterator it = bins->begin(); it != bins->end();) {
        if (it->name == name) {
            it = bins->erase(it);
            isSuccessful = true;
        } else {
            it++;
        }
    }

    // delete on cascade for exec bins in trigger config
    if (isSuccessful && this->triggerPolicy) {
        this->triggerPolicy->deleteExecBin(name);
    }

    return isSuccessful;
}
