// CUBE SDK

#ifndef CLI_EXT_STORAGE_CHANGER_H
#define CLI_EXT_STORAGE_CHANGER_H

#include "include/policy_notify.h"

static const char* LABEL_RESP_NAME_OLD = "Enter notification name (required): ";
static const char* LABEL_RESP_MATCH = "e.g. \"key\" == 'SYS00001I' OR \"severity\" == 'I'\nEnter notification match condition: ";
static const char* LABEL_RESP_SLACK_URL = "Enter slack URL: ";
static const char* LABEL_RESP_SLACK_CHANNEL = "Enter slack channel (optional): ";
static const char* LABEL_RESP_EMAIL_HOST = "Enter email host: ";
static const char* LABEL_RESP_EMAIL_PORT = "Enter email port: ";
static const char* LABEL_RESP_EMAIL_USER = "Enter email username: ";
static const char* LABEL_RESP_EMAIL_PASS = "Enter email password: ";
static const char* LABEL_RESP_EMAIL_FROM = "Enter email from email: ";
static const char* LABEL_RESP_EMAIL_TO = "Enter email to email list (comma separated): ";
static const char* LABEL_RESP_EXEC_TYPE = "Enter executable type: ";
static const char* LABEL_RESP_EXEC_MEDIA = "Select a media to upload executable: ";

class CliNotifyChanger
{
public:
    bool configure(OldNotifyPolicy *policy, int argc, const char** argv)
    {
        return construct(policy, argc, argv);
    }

private:
    bool checkResponseName(const NotifyConfig &cfg, const std::string& name)
    {
        if (!name.length()) {
            CliPrint("notification name is required\n");
            return false;
        }

        for (auto& b : cfg.resps) {
            if (name == b.name) {
                CliPrint("duplicate notification name\n");
                return false;
            }
        }

        return true;
    }

    bool construct(OldNotifyPolicy *policy, int argc, const char** argv)
    {
        CliList actions;
        int actIdx;
        std::string action;

        enum {
            ACTION_ADD = 0,
            ACTION_DELETE,
            ACTION_UPDATE
        };

        actions.push_back("add");
        actions.push_back("delete");
        actions.push_back("update");

        if(CliMatchListHelper(argc, argv, 1, actions, &actIdx, &action) != 0) {
            CliPrint("action type <add|delete|update> is missing or invalid");
            return false;
        }

        NotifyConfig cfg;
        policy->getNotifyConfig(&cfg);
        NotifyResponse resp;

        if (actIdx == ACTION_DELETE || actIdx == ACTION_UPDATE) {
            CliList respList;
            int respIdx;
            for (auto& r : cfg.resps)
                respList.push_back(r.name);

            if(CliMatchListHelper(argc, argv, 2, respList, &respIdx, &resp.name) != 0) {
                CliPrint("notification name is missing or not found");
                return false;
            }
        }
        else if (actIdx == ACTION_ADD) {
            if (!CliReadInputStr(argc, argv, 2, LABEL_RESP_NAME_OLD, &resp.name) ||
                !checkResponseName(cfg, resp.name)) {
                return false;
            }
        }

        int argIdx = 3;
        int selected;
        switch (actIdx) {
            case ACTION_DELETE:
                if (!policy->delResponse(resp.name)) {
                    CliPrintf("failed to delete notification: %s", resp.name.c_str());
                    return false;
                }
                break;
            case ACTION_UPDATE: {
                CliList enabled;
                std::string enStr;

                enabled.push_back("enabled");
                enabled.push_back("disabled");

                if(CliMatchListHelper(argc, argv, argIdx++, enabled, &selected, &enStr) != 0) {
                    CliPrint("invalid selection");
                    return false;
                }

                resp.enabled = (selected == 0) ? true : false;
            }
            case ACTION_ADD: {
                CliList topics, types;

                types.push_back("slack");
                types.push_back("email");
                types.push_back("exec");

                if(CliMatchListHelper(argc, argv, argIdx++, types, &selected, &resp.type) != 0) {
                    CliPrint("invalid type");
                    return false;
                }

                topics.push_back("events");
                topics.push_back("instance-events");

                if(CliMatchListHelper(argc, argv, argIdx++, topics, &selected, &resp.topic) != 0) {
                    CliPrint("invalid topic");
                    return false;
                }

                if (!CliReadInputStr(argc, argv, argIdx++, LABEL_RESP_MATCH, &resp.match) ||
                    resp.match.length() == 0) {
                    CliPrint("match is missing");
                    return false;
                }

                if (resp.type == "slack") {
                    if (!CliReadInputStr(argc, argv, argIdx++, LABEL_RESP_SLACK_URL, &resp.slackUrl) ||
                        resp.slackUrl.length() == 0) {
                        CliPrint("slack url is missing");
                        return false;
                    }
                    if (!CliReadInputStr(argc, argv, argIdx++, LABEL_RESP_SLACK_CHANNEL, &resp.slackChannel)) {
                        CliPrint("invalid channel name");
                        return false;
                    }
                }
                else if (resp.type == "email") {
                    if (!CliReadInputStr(argc, argv, argIdx++, LABEL_RESP_EMAIL_HOST, &resp.emailHost) ||
                        resp.emailHost.length() == 0) {
                        CliPrint("email host is missing");
                        return false;
                    }
                    std::string port;
                    if (!CliReadInputStr(argc, argv, argIdx++, LABEL_RESP_EMAIL_PORT, &port) ||
                        !HexParsePort(port.c_str(), &resp.emailPort)) {
                        CliPrint("email port is missing");
                        return false;
                    }
                    if (!CliReadInputStr(argc, argv, argIdx++, LABEL_RESP_EMAIL_USER, &resp.emailUser) ||
                        resp.emailUser.length() == 0) {
                        CliPrint("email username is missing");
                        return false;
                    }
                    if (!CliReadInputStr(argc, argv, argIdx++, LABEL_RESP_EMAIL_PASS, &resp.emailPass) ||
                        resp.emailPass.length() == 0) {
                        CliPrint("email password is missing");
                        return false;
                    }
                    if (!CliReadInputStr(argc, argv, argIdx++, LABEL_RESP_EMAIL_FROM, &resp.emailFrom) ||
                        resp.emailFrom.length() == 0) {
                        CliPrint("email 'from' field is missing");
                        return false;
                    }
                    if (!CliReadInputStr(argc, argv, argIdx++, LABEL_RESP_EMAIL_TO, &resp.emailTo) ||
                        resp.emailTo.length() == 0) {
                        CliPrint("email 'to' field is missing");
                        return false;
                    }
                }
                if (resp.type == "exec") {
                    CliList exts;

                    exts.push_back("shell");
                    exts.push_back("bin");

                    if(CliMatchListHelper(argc, argv, argIdx++, exts, &selected, &resp.execType, LABEL_RESP_EXEC_TYPE) != 0) {
                        CliPrint("invalid executable type [shell|bin]");
                        return false;
                    }


                    int index;
                    std::string media, dir, file, name;

                    if (CliMatchCmdHelper(argc, argv, argIdx++, "echo 'usb\nlocal'", &index, &media, LABEL_RESP_EXEC_MEDIA) != CLI_SUCCESS) {
                        CliPrintf("Unknown media");
                        return false;
                    }

                    if (index == 0 /* usb */) {
                        dir = "/mnt/usb";
                        CliPrintf("Insert a USB drive into the USB port on the appliance.");
                        if (!CliReadConfirmation())
                            return true;

                        AutoSignalHandlerMgt autoSignalHandlerMgt(UnInterruptibleHdr);
                        if (HexSpawnNoSig(UnInterruptibleHdr, (int)true, 0, HEX_CFG, "mount_usb", NULL) != 0) {
                            CliPrintf("Could not write to the USB drive. Please check the USB drive and retry the command.\n");
                            return true;
                        }
                    }
                    else if (index == 1 /* local */) {
                        dir = "/var/response";
                    }

                    // list files not dir
                    std::string cmd = "ls -p " + dir + " | grep -v /";
                    if (CliMatchCmdHelper(argc, argv, argIdx++, cmd, &index, &file) != CLI_SUCCESS) {
                        CliPrintf("no such file");
                        return false;
                    }

                    name = dir + "/" + file;
                    HexSystemF(0, "cp -f %s /var/alert_resp/exec_%s.%s", name.c_str(), resp.name.c_str(), resp.execType.c_str());
                }

                policy->setResponse(resp);
                break;
            }
        }

        return true;
    }
};

#endif /* endif CLI_EXT_STORAGE_CHANGER_H */


