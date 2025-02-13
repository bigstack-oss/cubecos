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

#include "include/policy_ext_storage.h"
#include "include/cli_ext_storage_changer.h"

static bool
ListBackends(const ExtStoragePolicy& policy)
{
    char line[116];
    memset(line, '-', sizeof(line));
    line[sizeof(line) - 1] = 0;

    ExtStorageConfig cfg;
    policy.getExtStorageConfig(&cfg);

#define HEADER_FMT "\n %7s  %15s  %15s  %15s  %15s  %20s  %15s\n"
#define BACKEND_FMT " %7s  %15s  %15s  %15s  %15s  %20s  %15s\n"

    printf(HEADER_FMT, "enabled", "name", "driver", "endpoint", "account", "secret", "pool");
    printf("%s\n", line);
    for (auto& b : cfg.backends)
        printf(BACKEND_FMT, CLI_ENABLE_STR(b.enabled), b.name.c_str(), b.driver.c_str(),
                               b.endpoint.c_str(), b.account.c_str(), b.secret.c_str(), b.pool.c_str());
    printf("\n");

    return true;
}

static int
BackendListMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="list" */)
        return CLI_INVALID_ARGS;

    HexPolicyManager policyManager;
    ExtStoragePolicy policy;
    if (!policyManager.load(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    ListBackends(policy);

    return CLI_SUCCESS;
}

static int
BackendCfgMain(int argc, const char** argv)
{
    if (argc > 8 /* [0]="configure", [1]=<add|delete|update>, [2]=<name>, [3~7]=<settings> */)
        return CLI_INVALID_ARGS;

    HexPolicyManager policyManager;
    ExtStoragePolicy policy;
    if (!policyManager.load(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    ListBackends(policy);

    CliExtStorageChanger changer;

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
CLI_MODE(CLI_TOP_MODE, "external-storage",
    "Work with external settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("external-storage", "list", BackendListMain, NULL,
        "List all external storage settings on the appliance.",
        "list");

CLI_MODE_COMMAND("external-storage", "configure", BackendCfgMain, NULL,
        "Configure external storage settings.",
        "configure [<add|delete|update>] [<name>] [<driver>] [<endpoint>] [<account>] [<secret>] [<pool>]");

