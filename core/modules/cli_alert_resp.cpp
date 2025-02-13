// HEX SDK

#include <unistd.h>

#include <map>

#include <netinet/in.h>
#include <arpa/inet.h>

#include <hex/log.h>
#include <hex/strict.h>
#include <hex/process.h>
#include <hex/cli_module.h>

#include <cube/cubesys.h>

#include "include/policy_notify.h"
#include "include/cli_notify_changer.h"

static bool
ListBackends(const NotifyPolicy& policy)
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

    ListBackends(policy);

    return CLI_SUCCESS;
}

static int
NotifyCfgMain(int argc, const char** argv)
{
    /*
     * [0]="configure", [1]=<add|delete|update>, [2]=<name>, [3]=[<enabled|disabled>],
     * [3/4]=<type>, [4/5]=<topic>, [5/6]=<match>, [6/7~11/12]=<settings>
     */
    if (argc > 13)
        return CLI_INVALID_ARGS;

    HexPolicyManager policyManager;
    NotifyPolicy policy;
    if (!policyManager.load(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    // ListBackends(policy);

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

// This mode is not available in STRICT error state
CLI_MODE(CLI_TOP_MODE, "notifications",
    "Work with notification settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("notifications", "list", NotifyListMain, NULL,
        "List all notifications settings on the appliance.",
        "list");

CLI_MODE_COMMAND("notifications", "configure", NotifyCfgMain, NULL,
        "Configure notifications settings.",
        "configure <add|delete|update> <name> [<enabled|disabled>] <slack|email|exec> <events|instance-events> <match>\n"
        "    slack: <url> [<channel>]\n"
        "    email: <host> <port> <username> <password> <from> <to>\n"
        "     exec: <local|usb> <filename> (upload to /var/response)");

