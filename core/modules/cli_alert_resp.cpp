// HEX SDK

#include <unistd.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <map>

#include <hex/log.h>
#include <hex/strict.h>
#include <hex/process.h>
#include <hex/string_util.h>
#include <hex/cli_module.h>

#include <cube/cubesys.h>

#include "include/policy_notify.h"
#include "include/cli_notify_changer.h"
#include "include/policy_notify_setting.h"
#include "include/policy_notify_trigger.h"

#define LABEL_SENDER_EMAIL_HOST "Enter email sender host: "
#define LABEL_SENDER_EMAIL_PORT "Enter email sender port: "
#define LABEL_SENDER_EMAIL_USERNAME "Enter email sender username [optional]: "
#define LABEL_SENDER_EMAIL_PASSWORD "Enter email sender password [optional]: "
#define LABEL_SENDER_EMAIL_FROM "Enter email sender from email address: "

#define LABEL_RECEIVER_EMAIL_ADDRESS "Enter email receiver to email address: "
#define LABEL_RECEIVER_EMAIL_NOTE "Enter email receiver note [optional]: "

#define LABEL_RECEIVER_SLACK_URL "Enter slack receiver url: "
#define LABEL_RECEIVER_SLACK_USERNAME "Enter slack receiver username: "
#define LABEL_RECEIVER_SLACK_DESCRIPTION "Enter slack receiver description [optional]: "
#define LABEL_RECEIVER_SLACK_WORKSPACE "Enter slack receiver workspace [optional]: "
#define LABEL_RECEIVER_SLACK_CHANNEL "Enter slack receiver channel [optional]: "

#define LABEL_RESP_NAME_CURRENT_OPTION_ONE "admin-notify"
#define LABEL_RESP_TOPIC_CURRENT_OPTION_ONE "events"
#define LABEL_RESP_MATCH_CURRENT_OPTION_ONE "\"severity\" == 'W' OR \"severity\" == 'E' OR \"severity\" == 'C'"
#define LABEL_RESP_NAME_CURRENT_OPTION_TWO "instance-notify"
#define LABEL_RESP_TOPIC_CURRENT_OPTION_TWO "instance-events"
#define LABEL_RESP_MATCH_CURRENT_OPTION_TWO "\"severity\" == 'W' OR \"severity\" == 'C'"
#define LABEL_RESP_NAME_CURRENT_LIMITATION "Currently, only \"" LABEL_RESP_NAME_CURRENT_OPTION_ONE "\" and \"" LABEL_RESP_NAME_CURRENT_OPTION_TWO "\" are supported.\n"
#define LABEL_RESP_NAME "Enter notification name: "
#define LABEL_RESP_EMAIL "Enter the email list (comma separated) [optional]: "
#define LABEL_RESP_SLACK "Enter the slack list (comma separated) [optional]: "
#define LABEL_RESP_EXEC_SHELL "Enter the exec shell list (comma separated) [optional]: "
#define LABEL_RESP_EXEC_BIN "Enter the exec bin list (comma separated) [optional]: "
#define LABEL_RESP_DESCRIPTION "Enter the notification description [optional]: "

static bool
listBackends(const NotifyPolicy& policy)
{
    char line[105];
    memset(line, '-', sizeof(line));
    line[sizeof(line) - 1] = 0;

    NotifyConfig cfg;
    policy.getNotifyConfig(&cfg);

#define HEADER_SLACK_FMT " %7s  %15s  %15s  %32s\n"
#define SLACK_FMT " %7s  %15s  %15s  %32s\n"

    printf("\nSLACK:\n");
    printf(HEADER_SLACK_FMT, "enabled", "name", "topic", "channel");
    printf("%s\n", line);
    for (auto& r : cfg.resps)
        if (r.type == "slack") {
            printf(SLACK_FMT, CLI_ENABLE_STR(r.enabled), r.name.c_str(), r.topic.c_str(), r.slackChannel.c_str());
            printf("          %15s: %s\n", "match", r.match.c_str());
            printf("          %15s: %s\n", "url", r.slackUrl.c_str());
        }

#define HEADER_EMAIL_FMT " %7s  %15s  %15s  %15s  %5s  %25s  %25s\n"
#define EMAIL_FMT " %7s  %15s  %15s  %15s  %5lu  %25s  %25s\n"

    printf("\nE-mail:\n");
    printf(HEADER_EMAIL_FMT, "enabled", "name", "topic", "host", "port", "username", "from");
    printf("%s\n", line);
    for (auto& r : cfg.resps)
        if (r.type == "email") {
            printf(EMAIL_FMT, CLI_ENABLE_STR(r.enabled), r.name.c_str(), r.topic.c_str(),
                              r.emailHost.c_str(), r.emailPort, r.emailUser.c_str(),
                              r.emailFrom.c_str());
            printf("          %15s: %s\n", "match", r.match.c_str());
            printf("          %15s: %s\n", "to", r.emailTo.c_str());
        }

    printf("\n");

#define HEADER_SLACK_FMT " %7s  %15s  %15s  %32s\n"
#define SLACK_FMT " %7s  %15s  %15s  %32s\n"

    printf("\nExecutable:\n");
    printf(HEADER_SLACK_FMT, "enabled", "name", "topic", "type");
    printf("%s\n", line);
    for (auto& r : cfg.resps)
        if (r.type == "exec") {
            printf(SLACK_FMT, CLI_ENABLE_STR(r.enabled), r.name.c_str(), r.topic.c_str(), r.execType.c_str());
            printf("          %15s: %s\n", "match", r.match.c_str());
        }

    printf("\n");

    return true;
}

static int
NotifyListMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="list" */)
        return CLI_INVALID_ARGS;

    HexPolicyManager policyManager;
    NotifyPolicy policy;
    if (!policyManager.load(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    listBackends(policy);

    return CLI_SUCCESS;
}

static int
NotifyCfgMain(int argc, const char** argv)
{
    /*
     * [0]="configure_old", [1]=<add|delete|update>, [2]=<name>, [3]=[<enabled|disabled>],
     * [3/4]=<type>, [4/5]=<topic>, [5/6]=<match>, [6/7~11/12]=<settings>
     */
    if (argc > 13)
        return CLI_INVALID_ARGS;

    HexPolicyManager policyManager;
    NotifyPolicy policy;
    if (!policyManager.load(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    // listBackends(policy);

    CliNotifyChanger changer;

    if (!changer.configure(&policy, argc, argv)) {
        return CLI_FAILURE;
    }

    if (!policyManager.save(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    // hex_config apply (translate + commit)
    if (!policyManager.apply()) {
        return CLI_UNEXPECTED_ERROR;
    }

    // should identify real user name
    //TODO: HexLogEvent("[user] modified external storage policy via cli");
    return CLI_SUCCESS;
}

bool
loadNotifyPolicy(HexPolicyManager& policyManager, NotifySettingPolicy& settingPolicy, NotifyTriggerPolicy& triggerPolicy)
{
    // load the existing policy file into policy
    // the trigger policy could only be loaded after setting the setting policy into the trigger policy
    if (!policyManager.load(settingPolicy)) {
        return false;
    }
    triggerPolicy.setSettingPolicy(&settingPolicy);
    if (!policyManager.load(triggerPolicy)) {
        return false;
    }
    settingPolicy.setTriggerPolicy(&triggerPolicy);
    return true;
}

bool
commitNotifyPolicy(HexPolicyManager& policyManager, NotifySettingPolicy& settingPolicy, NotifyTriggerPolicy& triggerPolicy)
{
    // save the updated policy into a policy file
    if (!policyManager.save(settingPolicy)) {
        return false;
    }
    if (!policyManager.save(triggerPolicy)) {
        return false;
    }

    // apply the udpated policy file
    if (!policyManager.apply()) {
        return false;
    }

    return true;
}

bool
putSettingSenderEmail(
    std::string host,
    std::string port,
    std::string username,
    std::string password,
    std::string from
)
{
    HexPolicyManager policyManager;
    NotifySettingPolicy policy;

    // load the existing policy file into policy
    if (!policyManager.load(policy)) {
        return false;
    }

    // update policy with input values
    policy.updateSenderEmail(host, port, username, password, from);

    // save the updated policy into a policy file
    if (!policyManager.save(policy)) {
        return false;
    }

    // apply the udpated policy file
    if (!policyManager.apply()) {
        return false;
    }
    return true;
}

bool
putSettingReceiverEmail(std::string address, std::string note)
{
    HexPolicyManager policyManager;
    NotifySettingPolicy policy;

    // load the existing policy file into policy
    if (!policyManager.load(policy)) {
        return false;
    }

    // update policy with input values
    policy.addOrUpdateReceiverEmail(address, note);

    // save the updated policy into a policy file
    if (!policyManager.save(policy)) {
        return false;
    }

    // apply the udpated policy file
    if (!policyManager.apply()) {
        return false;
    }
    return true;
}

bool
putSettingReceiverSlack(
    std::string url,
    std::string username,
    std::string description,
    std::string workspace,
    std::string channel
)
{
    HexPolicyManager policyManager;
    NotifySettingPolicy policy;

    // load the existing policy file into policy
    if (!policyManager.load(policy)) {
        return false;
    }

    // update policy with input values
    policy.addOrUpdateReceiverSlack(url, username, description, workspace, channel);

    // save the updated policy into a policy file
    if (!policyManager.save(policy)) {
        return false;
    }

    // apply the udpated policy file
    if (!policyManager.apply()) {
        return false;
    }
    return true;
}

bool
putSettingReceiverExecShell(std::string name)
{
    HexPolicyManager policyManager;
    NotifySettingPolicy policy;

    // load the existing policy file into policy
    if (!policyManager.load(policy)) {
        return false;
    }

    // update policy with input values
    policy.addReceiverExecShell(name);

    // save the updated policy into a policy file
    if (!policyManager.save(policy)) {
        return false;
    }

    // apply the udpated policy file
    if (!policyManager.apply()) {
        return false;
    }
    return true;
}

bool
putSettingReceiverExecBin(std::string name)
{
    HexPolicyManager policyManager;
    NotifySettingPolicy policy;

    // load the existing policy file into policy
    if (!policyManager.load(policy)) {
        return false;
    }

    // update policy with input values
    policy.addReceiverExecBin(name);

    // save the updated policy into a policy file
    if (!policyManager.save(policy)) {
        return false;
    }

    // apply the udpated policy file
    if (!policyManager.apply()) {
        return false;
    }
    return true;
}

bool
deleteSettingSenderEmail()
{
    HexPolicyManager policyManager;
    NotifySettingPolicy policy;

    // load the existing policy file into policy
    if (!policyManager.load(policy)) {
        return false;
    }

    // update policy with input values
    policy.deleteSenderEmail();

    // save the updated policy into a policy file
    if (!policyManager.save(policy)) {
        return false;
    }

    // apply the udpated policy file
    if (!policyManager.apply()) {
        return false;
    }
    return true;
}

bool
deleteSettingReceiverEmail(std::string address)
{
    HexPolicyManager policyManager;
    NotifySettingPolicy settingPolicy;
    NotifyTriggerPolicy triggerPolicy;
    if (!loadNotifyPolicy(policyManager, settingPolicy, triggerPolicy)) {
        return false;
    }

    // update policy with input values
    if (!settingPolicy.deleteReceiverEmail(address)) {
        return false;
    }

    if (!commitNotifyPolicy(policyManager, settingPolicy, triggerPolicy)) {
        return false;
    }

    return true;
}

bool
deleteSettingReceiverSlack(std::string url)
{
    HexPolicyManager policyManager;
    NotifySettingPolicy settingPolicy;
    NotifyTriggerPolicy triggerPolicy;
    if (!loadNotifyPolicy(policyManager, settingPolicy, triggerPolicy)) {
        return false;
    }

    // update policy with input values
    if (!settingPolicy.deleteReceiverSlack(url)) {
        return false;
    }

    if (!commitNotifyPolicy(policyManager, settingPolicy, triggerPolicy)) {
        return false;
    }

    return true;
}

bool
deleteSettingReceiverExecShell(std::string name)
{
    HexPolicyManager policyManager;
    NotifySettingPolicy settingPolicy;
    NotifyTriggerPolicy triggerPolicy;
    if (!loadNotifyPolicy(policyManager, settingPolicy, triggerPolicy)) {
        return false;
    }

    // update policy with input values
    if (!settingPolicy.deleteReceiverExecShell(name)) {
        return false;
    }

    if (!commitNotifyPolicy(policyManager, settingPolicy, triggerPolicy)) {
        return false;
    }

    return true;
}

bool
deleteSettingReceiverExecBin(std::string name)
{
    HexPolicyManager policyManager;
    NotifySettingPolicy settingPolicy;
    NotifyTriggerPolicy triggerPolicy;
    if (!loadNotifyPolicy(policyManager, settingPolicy, triggerPolicy)) {
        return false;
    }

    // update policy with input values
    if (!settingPolicy.deleteReceiverExecBin(name)) {
        return false;
    }

    if (!commitNotifyPolicy(policyManager, settingPolicy, triggerPolicy)) {
        return false;
    }

    return true;
}

static int
NotifySettingMain(int argc, const char** argv)
{
    /**
     * argv[0]="configure"
     * argv[1]=<add|update|delete>
     * argv[2]=<sender|receiver>
     */

    CliList actions;
    actions.push_back("add");
    actions.push_back("update");
    actions.push_back("delete");

    int actionIndex;
    enum {
        ACTION_ADD = 0,
        ACTION_UPDATE,
        ACTION_DELETE
    };

    std::string action;

    if (CliMatchListHelper(argc, argv, 1, actions, &actionIndex, &action) != 0) {
        CliPrint("action type <add|update|delete> is missing or invalid");
        return CLI_INVALID_ARGS;
    }

    CliList roles;
    roles.push_back("sender");
    roles.push_back("receiver");

    int roleIndex;
    enum {
        TYPE_SENDER = 0,
        TYPE_RECEIVER
    };

    std::string role;

    if (CliMatchListHelper(argc, argv, 2, roles, &roleIndex, &role) != 0) {
        CliPrint("role type <sender|receiver> is missing or invalid");
        return CLI_INVALID_ARGS;
    }

    if (actionIndex == ACTION_ADD || actionIndex == ACTION_UPDATE) {
        if (roleIndex == TYPE_SENDER) {
            /**
             * argv[3]="email"
             * argv[4]=<host>
             * argv[5]=<port>
             * argv[6]=<username>
             * argv[7]=<password>
             * argv[8]=<from>
             */

            CliList senderTypes;
            senderTypes.push_back("email");

            int senderTypeIndex;
            enum {
                SENDER_TYPE_EMAIL = 0
            };

            std::string senderType;
            std::string host;
            std::string port;
            std::string username;
            std::string password;
            std::string from;

            if (CliMatchListHelper(argc, argv, 3, senderTypes, &senderTypeIndex, &senderType) != 0) {
                CliPrint("sender type is missing or invalid");
                return CLI_INVALID_ARGS;
            }

            if (!CliReadInputStr(argc, argv, 4, LABEL_SENDER_EMAIL_HOST, &host) || host.length() == 0) {
                CliPrint("email sender host is missing");
                return CLI_INVALID_ARGS;
            }

            if (!CliReadInputStr(argc, argv, 5, LABEL_SENDER_EMAIL_PORT, &port) || port.length() == 0) {
                CliPrint("email sender port is missing");
                return CLI_INVALID_ARGS;
            }

            // we allow username to be blank here
            if (!CliReadInputStr(argc, argv, 6, LABEL_SENDER_EMAIL_USERNAME, &username)) {
                CliPrint("email sender username is missing");
                return CLI_INVALID_ARGS;
            }

            // we allow password to be blank here
            if (!CliReadInputStr(argc, argv, 7, LABEL_SENDER_EMAIL_PASSWORD, &password)) {
                CliPrint("email sender password is missing");
                return CLI_INVALID_ARGS;
            }

            if (!CliReadInputStr(argc, argv, 8, LABEL_SENDER_EMAIL_FROM, &from) || from.length() == 0) {
                CliPrint("email sender from address is missing");
                return CLI_INVALID_ARGS;
            }

            if (!putSettingSenderEmail(host, port, username, password, from)) {
                return CLI_UNEXPECTED_ERROR;
            }
        } else {
            /**
             * argv[3]=<email|slack|exec>
             */

            CliList receiverTypes;
            receiverTypes.push_back("email");
            receiverTypes.push_back("slack");
            receiverTypes.push_back("exec");

            int receiverTypeIndex;
            enum {
                RECEIVER_TYPE_EMAIL = 0,
                RECEIVER_TYPE_SLACK,
                RECEIVER_TYPE_EXEC
            };

            std::string receiverType;

            if (CliMatchListHelper(argc, argv, 3, receiverTypes, &receiverTypeIndex, &receiverType) != 0) {
                CliPrint("receiver type is missing or invalid");
                return CLI_INVALID_ARGS;
            }

            if (receiverTypeIndex == RECEIVER_TYPE_EMAIL) {
                /**
                 * argv[4]=<address>
                 * argv[5]=[<note>]
                 */

                std::string address;
                std::string note;

                if (!CliReadInputStr(argc, argv, 4, LABEL_RECEIVER_EMAIL_ADDRESS, &address) || address.length() == 0) {
                    CliPrint("email receiver to address is missing");
                    return CLI_INVALID_ARGS;
                }

                CliReadInputStr(argc, argv, 5, LABEL_RECEIVER_EMAIL_NOTE, &note);

                if (!putSettingReceiverEmail(address, note)) {
                    return CLI_UNEXPECTED_ERROR;
                }
            } else if (receiverTypeIndex == RECEIVER_TYPE_SLACK) {
                /**
                 * argv[4]=<url>
                 * argv[5]=<username>
                 * argv[6]=[<description>]
                 * argv[7]=[<workspace>]
                 * argv[8]=[<channel>]
                 */
                
                std::string url;
                std::string username;
                std::string description;
                std::string workspace;
                std::string channel;

                if (!CliReadInputStr(argc, argv, 4, LABEL_RECEIVER_SLACK_URL, &url) || url.length() == 0) {
                    CliPrint("slack receiver url is missing");
                    return CLI_INVALID_ARGS;
                }

                if (!CliReadInputStr(argc, argv, 5, LABEL_RECEIVER_SLACK_USERNAME, &username) || username.length() == 0) {
                    CliPrint("slack receiver username is missing");
                    return CLI_INVALID_ARGS;
                }

                CliReadInputStr(argc, argv, 6, LABEL_RECEIVER_SLACK_DESCRIPTION, &description);
                CliReadInputStr(argc, argv, 7, LABEL_RECEIVER_SLACK_WORKSPACE, &workspace);
                CliReadInputStr(argc, argv, 8, LABEL_RECEIVER_SLACK_CHANNEL, &channel);

                if (!putSettingReceiverSlack(url, username, description, workspace, channel)) {
                    return CLI_UNEXPECTED_ERROR;
                }
            } else {
                /**
                 * argv[4]=<shell|bin>
                 * argv[5]=<usb|local>
                 * argv[6]=<file>
                 */

                CliList execTypes;
                execTypes.push_back("shell");
                execTypes.push_back("bin");

                int execTypeIndex;
                enum {
                    EXEC_TYPE_SHELL = 0,
                    EXEC_TYPE_BIN
                };

                std::string execType;

                if (CliMatchListHelper(argc, argv, 4, execTypes, &execTypeIndex, &execType) != 0) {
                    CliPrint("exec type is missing or invalid");
                    return CLI_INVALID_ARGS;
                }

                CliList execFileDirectories;
                execFileDirectories.push_back("usb");
                execFileDirectories.push_back("local");

                int execFileDirectoryIndex;
                enum {
                    FILE_DIRECTORY_USB = 0,
                    FILE_DIRECTORY_LOCAL
                };

                std::string execFileDirectory;

                if(CliMatchListHelper(argc, argv, 5, execFileDirectories, &execFileDirectoryIndex, &execFileDirectory) != 0) {
                    CliPrint("file directory is missing or invalid");
                    return CLI_INVALID_ARGS;
                }

                std::string dir;
                if (execFileDirectoryIndex == FILE_DIRECTORY_USB) {
                    dir = "/mnt/usb";
                    CliPrintf("Insert a USB drive into the USB port on the appliance.");
                    if (!CliReadConfirmation()) {
                        return CLI_SUCCESS;
                    }

                    AutoSignalHandlerMgt autoSignalHandlerMgt(UnInterruptibleHdr);
                    if (HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "mount_usb", NULL) != 0) {
                        CliPrintf("Could not access the USB drive. Please check the USB drive and retry the command.\n");
                        return CLI_UNEXPECTED_ERROR;
                    }
                } else {
                    dir = "/var/response";
                }

                // list files not directory
                std::string cmd = "ls -p " + dir + " | grep -v /";
                int execFileIndex;
                std::string execFile;
                if (CliMatchCmdHelper(argc, argv, 6, cmd, &execFileIndex, &execFile) != 0) {
                    CliPrintf("no such file");
                    return CLI_UNEXPECTED_ERROR;
                }

                std::string fullPath = dir + "/" + execFile;
                std::string execName = execFile;
                std::size_t dotPosition = execName.find_first_of('.');
                if (dotPosition != std::string::npos) {
                    // remove the file extension, e.g., aaa.bbb => aaa
                    execName.erase(dotPosition);
                }
                HexSystemF(0, "cp -f %s /var/alert_resp/exec_%s.%s", fullPath.c_str(), execName.c_str(), execType.c_str());
                if (execFileDirectoryIndex == FILE_DIRECTORY_USB) {
                    HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "umount_usb", NULL);
                }

                if (execTypeIndex == EXEC_TYPE_SHELL) {
                    if (!putSettingReceiverExecShell(execName)) {
                        return CLI_UNEXPECTED_ERROR;
                    }
                } else if (execTypeIndex == EXEC_TYPE_BIN) {
                    if (!putSettingReceiverExecBin(execName)) {
                        return CLI_UNEXPECTED_ERROR;
                    }
                } else {
                    return CLI_INVALID_ARGS;
                }
            }
        }
    } else {
        if (roleIndex == TYPE_SENDER) {
            /**
             * argv[3]="email"
             */
            CliList senderTypes;
            senderTypes.push_back("email");

            int senderTypeIndex;
            enum {
                SENDER_TYPE_EMAIL = 0
            };

            std::string senderType;

            if (CliMatchListHelper(argc, argv, 3, senderTypes, &senderTypeIndex, &senderType) != 0) {
                CliPrint("sender type is missing or invalid");
                return CLI_INVALID_ARGS;
            }

            if (!deleteSettingSenderEmail()) {
                return CLI_UNEXPECTED_ERROR;
            }
        } else {
            /**
             * argv[3]=<email|slack|exec>
             */
            
            CliList receiverTypes;
            receiverTypes.push_back("email");
            receiverTypes.push_back("slack");
            receiverTypes.push_back("exec");

            int receiverTypeIndex;
            enum {
                RECEIVER_TYPE_EMAIL = 0,
                RECEIVER_TYPE_SLACK,
                RECEIVER_TYPE_EXEC
            };

            std::string receiverType;

            if (CliMatchListHelper(argc, argv, 3, receiverTypes, &receiverTypeIndex, &receiverType) != 0) {
                CliPrint("receiver type is missing or invalid");
                return CLI_INVALID_ARGS;
            }

            if (receiverTypeIndex == RECEIVER_TYPE_EMAIL) {
                /**
                 * argv[4]=<address>
                 */

                std::string address;

                if (!CliReadInputStr(argc, argv, 4, LABEL_RECEIVER_EMAIL_ADDRESS, &address) || address.length() == 0) {
                    CliPrint("email receiver to address is missing");
                    return CLI_INVALID_ARGS;
                }

                if (!deleteSettingReceiverEmail(address)) {
                    return CLI_UNEXPECTED_ERROR;
                }
            } else if (receiverTypeIndex == RECEIVER_TYPE_SLACK) {
                /**
                 * argv[4]=<url>
                 */

                std::string url;

                if (!CliReadInputStr(argc, argv, 4, LABEL_RECEIVER_SLACK_URL, &url) || url.length() == 0) {
                    CliPrint("slack receiver url is missing");
                    return CLI_INVALID_ARGS;
                }

                if (!deleteSettingReceiverSlack(url)) {
                    return CLI_UNEXPECTED_ERROR;
                }
            } else {
                /**
                 * argv[4]=<file>
                 */
                
                 // list files (/var/alert_resp/exec_*)
                std::string cmd = "ls -p /var/alert_resp/ | grep -v / | grep exec_ | sed 's/^exec_//'";
                int execFileIndex;
                std::string execFile;
                if (CliMatchCmdHelper(argc, argv, 4, cmd, &execFileIndex, &execFile) != 0) {
                    CliPrintf("no such file");
                    return CLI_UNEXPECTED_ERROR;
                }

                std::string execName = "";
                std::string execType = "";
                std::size_t dotPositionOne = execFile.find_first_of('.');
                if (dotPositionOne != std::string::npos) {
                    execName = execFile.substr(0, dotPositionOne);

                    std::size_t dotPositionTwo = execFile.find_last_of('.');
                    if (dotPositionTwo != std::string::npos) {
                        if (dotPositionOne != dotPositionTwo) {
                            return CLI_UNEXPECTED_ERROR;
                        }

                        if ((dotPositionTwo + 1) < execFile.length()) {
                            execType = execFile.substr(dotPositionTwo + 1);
                        }
                    }
                } else {
                    execName = execFile;
                }

                if (execType == "shell") {
                    if (!deleteSettingReceiverExecShell(execName)) {
                        return CLI_UNEXPECTED_ERROR;
                    }
                } else if (execType == "bin") {
                    if (!deleteSettingReceiverExecBin(execName)) {
                        return CLI_UNEXPECTED_ERROR;
                    }
                } else {
                    return CLI_INVALID_ARGS;
                }
            }
        }
    }

    return CLI_SUCCESS;
}

bool
putTrigger(
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
    HexPolicyManager policyManager;
    NotifySettingPolicy settingPolicy;
    NotifyTriggerPolicy triggerPolicy;
    if (!loadNotifyPolicy(policyManager, settingPolicy, triggerPolicy)) {
        return false;
    }

    // update policy with input values
    triggerPolicy.addOrUpdateTrigger(
        name,
        enabled,
        topic,
        match,
        description,
        emails,
        slacks,
        execShells,
        execBins
    );

    if (!commitNotifyPolicy(policyManager, settingPolicy, triggerPolicy)) {
        return false;
    }

    return true;
}

bool
deleteTrigger(std::string name)
{
    HexPolicyManager policyManager;
    NotifyTriggerPolicy policy;

    // load the existing policy file into policy
    if (!policyManager.load(policy)) {
        return false;
    }

    // update policy with input values
    // should not delete admin-notify and instance-notify, reset them instead
    if (name.compare(LABEL_RESP_NAME_CURRENT_OPTION_ONE) == 0) {
        policy.addOrUpdateTrigger(
            name,
            false,
            LABEL_RESP_TOPIC_CURRENT_OPTION_ONE,
            LABEL_RESP_MATCH_CURRENT_OPTION_ONE,
            "",
            std::vector<std::string>(),
            std::vector<std::string>(),
            std::vector<std::string>(),
            std::vector<std::string>()
        );
    } else if (name.compare(LABEL_RESP_NAME_CURRENT_OPTION_TWO) == 0) {
        policy.addOrUpdateTrigger(
            name,
            false,
            LABEL_RESP_TOPIC_CURRENT_OPTION_TWO,
            LABEL_RESP_MATCH_CURRENT_OPTION_TWO,
            "",
            std::vector<std::string>(),
            std::vector<std::string>(),
            std::vector<std::string>(),
            std::vector<std::string>()
        );
    } else {
        if (!policy.deleteTrigger(name)) {
            return false;
        }
    }

    // save the updated policy into a policy file
    if (!policyManager.save(policy)) {
        return false;
    }

    // apply the udpated policy file
    if (!policyManager.apply()) {
        return false;
    }
    return true;
}

static int
NotifyTriggerMain(int argc, const char** argv)
{
    /**
     * argv[0]="set_trigger"
     * argv[1]=<add|update|delete>
     */

    CliList actions;
    actions.push_back("add");
    actions.push_back("update");
    actions.push_back("delete");

    int actionIndex;
    enum {
        ACTION_ADD = 0,
        ACTION_UPDATE,
        ACTION_DELETE
    };

    std::string action;

    if (CliMatchListHelper(argc, argv, 1, actions, &actionIndex, &action) != 0) {
        CliPrint("action type <add|update|delete> is missing or invalid");
        return CLI_INVALID_ARGS;
    }

    if (actionIndex == ACTION_ADD || actionIndex == ACTION_UPDATE) {
        /**
         * argv[2]=<name>
         */

        CliPrint(LABEL_RESP_NAME_CURRENT_LIMITATION);

        std::string name;
        if (!CliReadInputStr(argc, argv, 2, LABEL_RESP_NAME, &name) || name.length() == 0) {
            CliPrint("alert response name is missing");
            return CLI_INVALID_ARGS;
        }

        if (
            name.compare(LABEL_RESP_NAME_CURRENT_OPTION_ONE) != 0 &&
            name.compare(LABEL_RESP_NAME_CURRENT_OPTION_TWO) != 0
        ) {
            CliPrint("the name is not supported");
            return CLI_INVALID_ARGS;
        }

        std::string topic = "";
        std::string match = "";
        if (name.compare(LABEL_RESP_NAME_CURRENT_OPTION_ONE) == 0) {
            topic = LABEL_RESP_TOPIC_CURRENT_OPTION_ONE;
            match = LABEL_RESP_MATCH_CURRENT_OPTION_ONE;
        } else if (name.compare(LABEL_RESP_NAME_CURRENT_OPTION_TWO) == 0) {
            topic = LABEL_RESP_TOPIC_CURRENT_OPTION_TWO;
            match = LABEL_RESP_MATCH_CURRENT_OPTION_TWO;
        }

        /**
         * argv[3]=<enable|disable>
         * argv[4]=[<email address 1, email address 2>]
         * argv[5]=[<slack url 1, slack url 2>]
         * argv[6]=[<exec shell 1, exec shell 2>]
         * argv[7]=[<exec bin 1, exec bin 2>]
         * argv[8]=[<description>]
         */

        CliList enables;
        enables.push_back("enable");
        enables.push_back("disable");

        int enableIndex;
        enum {
            ENABLE_TRUE = 0,
            ENABLE_FALSE
        };

        std::string enable;

        if (CliMatchListHelper(argc, argv, 3, enables, &enableIndex, &enable) != 0) {
            CliPrint("<enable|disable> is missing or invalid");
            return CLI_INVALID_ARGS;
        }

        bool enabled = (enable == "enable");
        std::string emailInput;
        std::string slackInput;
        std::string execShellInput;
        std::string execBinInput;

        CliReadInputStr(argc, argv, 4, LABEL_RESP_EMAIL, &emailInput);
        CliReadInputStr(argc, argv, 5, LABEL_RESP_SLACK, &slackInput);
        CliReadInputStr(argc, argv, 6, LABEL_RESP_EXEC_SHELL, &execShellInput);
        CliReadInputStr(argc, argv, 7, LABEL_RESP_EXEC_BIN, &execBinInput);

        std::vector<std::string> emails = hex_string_util::split(emailInput, ',');
        std::vector<std::string> slacks = hex_string_util::split(slackInput, ',');
        std::vector<std::string> execShells = hex_string_util::split(execShellInput, ',');
        std::vector<std::string> execBins = hex_string_util::split(execBinInput, ',');

        std::string description;
        CliReadInputStr(argc, argv, 8, LABEL_RESP_DESCRIPTION, &description);

        if (!putTrigger(name, enabled, topic, match, description, emails, slacks, execShells, execBins)) {
            return CLI_UNEXPECTED_ERROR;
        }
    } else {
        /**
         * argv[2]=<name>
         */
        
        CliPrint(LABEL_RESP_NAME_CURRENT_LIMITATION);

        std::string name;
        if (!CliReadInputStr(argc, argv, 2, LABEL_RESP_NAME, &name) || name.length() == 0) {
            CliPrint("alert response name is missing");
            return CLI_INVALID_ARGS;
        }

        if (
            name.compare(LABEL_RESP_NAME_CURRENT_OPTION_ONE) != 0 &&
            name.compare(LABEL_RESP_NAME_CURRENT_OPTION_TWO) != 0
        ) {
            CliPrint("the name is not supported");
            return CLI_INVALID_ARGS;
        }

        if (!deleteTrigger(name)) {
            return CLI_UNEXPECTED_ERROR;
        }
    }

    return CLI_SUCCESS;
}

// This mode is not available in STRICT error state
CLI_MODE(CLI_TOP_MODE, "notifications",
    "Work with notification settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("notifications", "list", NotifyListMain, NULL,
    "List all notifications settings on the appliance.",
    "list");

CLI_MODE_COMMAND("notifications", "configure_old", NotifyCfgMain, NULL,
    "Configure notifications settings.",
    "configure_old <add|delete|update> <name> [<enabled|disabled>] <slack|email|exec> <events|instance-events> <match>\n"
    "    slack: <url> [<channel>]\n"
    "    email: <host> <port> <username> <password> <from> <to>\n"
    "     exec: <local|usb> <filename> (upload to /var/response)");

CLI_MODE_COMMAND("notifications", "configure", NotifySettingMain, NULL,
    "Configure notifications settings.",
    "configure <add|update|delete>\n"
    "    <add|update>: <sender|receiver>\n"
    "        sender: email <host> <port> <username> <password> <from>\n"
    "        receiver: <email|slack|exec>\n"
    "            email: <address> [<note>]\n"
    "            slack: <url> <username> [<description>] [<workspace>] [<channel>]\n"
    "            exec: <shell|bin> <usb|local> <file>\n"
    "The file needs to be in either the usb or /var/response (local) for exec.\n"
    "    delete: <sender|receiver|exec>\n"
    "        sender: email\n"
    "        receiver: <email|slack>\n"
    "            email: <address>\n"
    "            slack: <url>\n"
    "            exec: <file>");

CLI_MODE_COMMAND("notifications", "set_trigger", NotifyTriggerMain, NULL,
    "Configure notifications triggers.",
    "set_trigger <add|update|delete>\n"
    "    <add|update>: <name>\n"
    "        admin-notify: <enable|disable> [<email address 1, email address 2>] [<slack url 1, slack url 2>] [<exec shell 1, exec shell 2>] [<exec bin 1, exec bin 2>] [<description>]\n"
    "        instance-notify: <enable|disable> [<email address 1, email address 2>] [<slack url 1, slack url 2>] [<exec shell 1, exec shell 2>] [<exec bin 1, exec bin 2>] [<description>]\n"
    "    delete: <name>");
