// CUBE SDK

#include "include/policy_notify_setting.h"

NotifySettingPolicy::NotifySettingPolicy():
    isInitialized(false),
    ymlRoot(nullptr)
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

    NotifySettingReceiver r;
    r.emails = std::vector<NotifySettingReceiverEmail>();
    r.slacks = std::vector<NotifySettingReceiverSlack>();
    this->config.receiver = r;
}

NotifySettingPolicy::~NotifySettingPolicy()
{
    if (this->ymlRoot != nullptr) {
        FiniYml(this->ymlRoot);
    }
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

const NotifySettingConfig
NotifySettingPolicy::getConfig() const
{
    return this->config;
}

bool
NotifySettingPolicy::load(const char* policyFile)
{
    this->isInitialized = false;
    if (this->ymlRoot != nullptr) {
        FiniYml(this->ymlRoot);
    }
    this->ymlRoot = InitYml(policyFile);
    if (ReadYml(policyFile, this->ymlRoot) < 0) {
        FiniYml(this->ymlRoot);
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
    for (std::size_t i = 0; i < receiverEmailCount; i++) {
        std::size_t ymlIndex = i + 1;

        NotifySettingReceiverEmail e;
        HexYmlParseString(e.address, this->ymlRoot, "receiver.emails.%d.address", ymlIndex);
        HexYmlParseString(e.note, this->ymlRoot, "receiver.emails.%d.note", ymlIndex);

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

        this->config.receiver.emails.push_back(e);
        receiverEmailAddressSet.insert(e.address);
    }

    // receiver slack
    std::set<std::string> receiverSlackUrlSet;
    std::size_t receiverSlackCount = SizeOfYmlSeq(this->ymlRoot, "receiver.slacks");
    for (std::size_t i = 0; i < receiverSlackCount; i++) {
        std::size_t ymlIndex = i + 1;

        NotifySettingReceiverSlack s;
        HexYmlParseString(s.url, this->ymlRoot, "receiver.slacks.%d.url", ymlIndex);
        HexYmlParseString(s.username, this->ymlRoot, "receiver.slacks.%d.username", ymlIndex);
        HexYmlParseString(s.description, this->ymlRoot, "receiver.slacks.%d.description", ymlIndex);
        HexYmlParseString(s.workspace, this->ymlRoot, "receiver.slacks.%d.workspace", ymlIndex);
        HexYmlParseString(s.channel, this->ymlRoot, "receiver.slacks.%d.channel", ymlIndex);

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

        this->config.receiver.slacks.push_back(s);
        receiverSlackUrlSet.insert(s.url);
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

    return WriteYml(policyFile, this->ymlRoot) == 0;
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

    return isSuccessful;
}
