// HEX SDK

#include <hex/strict.h>

#include <hex/cli_module.h>

#include "include/cli_ntp_changer.h"
#include "include/policy_ntp.h"

static int
ServerShowMain(int argc, const char** argv)
{
    HexPolicyManager policyManager;
    NtpPolicy policy;
    if (!policyManager.load(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    CliPrintf("%s", policy.getServer());

    return CLI_SUCCESS;
}

static int
ServerSetMain(int argc, const char** argv)
{
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    CliNtpChanger changer;
    std::string server;
    bool validated = false;

    if (argc == 2) {
        server = argv[1];
        validated = changer.validate(server);
    }
    else {
        validated = changer.configure(&server);
    }

    if (!validated) {
        return CLI_FAILURE;
    }

    HexPolicyManager policyManager;
    NtpPolicy policy;
    if (!policyManager.load(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    if (!policy.setServer(server)) {
        return CLI_UNEXPECTED_ERROR;
    }

    if (!policyManager.save(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    if (!policyManager.apply()) {
        return CLI_UNEXPECTED_ERROR;
    }

    return CLI_SUCCESS;
}

// This mode is not available in STRICT error state
CLI_MODE("management", "ntp", "Work with NTP settings.", !HexStrictIsErrorState() && !FirstTimeSetupRequired());

CLI_MODE_COMMAND("ntp", "show", ServerShowMain, NULL,
        "Show the current NTP server.",
        "show");

CLI_MODE_COMMAND("ntp", "set", ServerSetMain, NULL,
        "Set the NTP server.",
        "set [ <server> ]");

