// CUBE SDK
#include <iostream>
#include <string>
#include <vector>
#include <sstream>

#include <sys/stat.h>

#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/log.h>
#include <hex/strict.h>
#include <hex/parse.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

#include <cube/cubesys.h>

#define K3S_ADMIN_DIRECT_CONTROL_ENABLED "/etc/appliance/state/k3s_admin_direct_control_enabled"

static const std::string CMD_LIST_NON_SYSTEM_NAMESPACE = "kubectl get ns -l 'app.kubernetes.io/managed-by=cube' -o custom-columns=NAME:.metadata.name --no-headers";
static const char* HINT_INPUT_CPU = "Input cpu quota(unit can be integer, floating or milli-cpu. e.g. 1 = 1 core, 1500 = 1.5 cores, and 2000m = 2 cores): ";
static const char* HINT_INPUT_MEMORY = "Input memory quota(unit can be Ki, Mi, and Gi. first letter should be capitalized): ";
static const char* HINT_INPUT_STORAGE = "Input storage quota(unit can be Ki, Mi, and Gi. first letter should be capitalized): ";

std::string
joinArgv(int argc, const char** argv, const std::string& delimiter = " ") {
    std::string result;

    for (int i = 1; i < argc; ++i) {
        result += argv[i];
        if (i < argc - 1) {
            result += delimiter;
        }
    }

    return result;
}

bool
isReadyToOperateUser()
{
    std::string answer;
    CliPrintf("Ready to operate with the selected namespaces?");
    bool result = CliReadLine("Enter 'y' to operate, or 'n' to append other namespaces: ", answer);
    if (result && answer == "y") {
        return true;
    }

    return false;
}

std::string
joinWithComma(const std::vector<std::string>& elements) {
    if (elements.empty()) {
        return "";
    }

    std::ostringstream oss;
    for (size_t i = 0; i < elements.size(); ++i) {
        if (i != 0) {
            oss << ",";
        }
        oss << elements[i];
    }

    return oss.str();
}

std::string
cliSelectNamespacesToUser()
{
    int index;
    std::vector<std::string> namespaces;

    while (true) {
        std::string ns;
        int ret = CliMatchCmdHelper(0, NULL, 0, CMD_LIST_NON_SYSTEM_NAMESPACE, &index,  &ns, "Select namespace to operate: ");
        if (ret != CLI_SUCCESS) {
            CliPrintf("Unknown namespace, please select the listed index above.");
            continue;
        }

        namespaces.push_back(ns);
        if (isReadyToOperateUser()) {
            break;
        }
    }

    return joinWithComma(namespaces);
}

static int
k3sGetResourceOverviewMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="namespace_list" */) {
        return CLI_INVALID_ARGS;
    }

    if (HexSystemF(0, "cubectl config k3s resource-overview-get") != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
k3sNamespaceListMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="namespace_list" */) {
        return CLI_INVALID_ARGS;
    }

    if (HexSystemF(0, "cubectl config k3s namespace-list --non-system-namespace=true") != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
k3sNamespaceCreateMain(int argc, const char** argv)
{
    if (argc > 5 /* [1]="NAMESPACE", [2]="CPU QUOTA", [3]="MEMORY QUOTA", [4]="STORAGE QUOTA" */) {
        return CLI_INVALID_ARGS;
    }

    std::string ns, cpuQuota, memoryQuota, storageQuota;
    if (HexSystemF(0, "cubectl config k3s available-resources-get") != 0) {
        CliPrintf("Failed to get k3s available resources");
        return CLI_FAILURE;
    }

    if (!CliReadInputStr(argc, argv, 1, "Input name for new namespace: ", &ns) || ns.length() <= 0) {
        CliPrint("namespace name is required");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 2, HINT_INPUT_CPU, &cpuQuota) || cpuQuota.length() <= 0) {
        CliPrint("cpu quota is required");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 3, HINT_INPUT_MEMORY, &memoryQuota) || memoryQuota.length() <= 0) {
        CliPrint("memory quota is required");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 4, HINT_INPUT_STORAGE, &storageQuota) || storageQuota.length() <= 0) {
        CliPrint("storage quota is required");
        return CLI_INVALID_ARGS;
    }

    int result = HexSystemF(0, "cubectl config k3s namespace-create %s --cpu %s --memory %s --ephemeral-storage %s", ns.c_str(), cpuQuota.c_str(), memoryQuota.c_str(), storageQuota.c_str());
    if (result != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
k3sNamespaceUpdateMain(int argc, const char** argv)
{
    if (argc > 5 /* [1]="NAMESPACE", [2]="CPU QUOTA", [3]="MEMORY QUOTA", [4]="STORAGE QUOTA" */) {
        return CLI_INVALID_ARGS;
    }

    std::string ns, cpuQuota, memoryQuota, storageQuota;
    if (HexSystemF(0, "cubectl config k3s available-resources-get") != 0) {
        CliPrintf("Failed to get k3s available resources");
        return CLI_FAILURE;
    }

    int index;
    if(CliMatchCmdHelper(argc, argv, 1, "cubectl config k3s namespace-list --non-system-namespace=true --no-header=true --no-quota=true", &index, &ns, "Select the namespace to update") != CLI_SUCCESS) {
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 2, HINT_INPUT_CPU, &cpuQuota) || cpuQuota.length() <= 0) {
        CliPrint("cpu quota is required");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 3, HINT_INPUT_MEMORY, &memoryQuota) || memoryQuota.length() <= 0) {
        CliPrint("memory quota is required");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 4, HINT_INPUT_STORAGE, &storageQuota) || storageQuota.length() <= 0) {
        CliPrint("storage quota is required");
        return CLI_INVALID_ARGS;
    }

    int result = HexSystemF(0, "cubectl config k3s namespace-update %s --cpu %s --memory %s --ephemeral-storage %s", ns.c_str(), cpuQuota.c_str(), memoryQuota.c_str(), storageQuota.c_str());
    if (result != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
k3sNamespaceDeleteMain(int argc, const char** argv)
{
    if (argc > 2 /* [1]="NAMESPACE" */) {
        return CLI_INVALID_ARGS;
    }

    int index;
    std::string ns;
    if(CliMatchCmdHelper(argc, argv, 1, "cubectl config k3s namespace-list --non-system-namespace=true --no-header=true --no-quota=true", &index, &ns, "Select the namespace to delete") != CLI_SUCCESS) {
        return CLI_INVALID_ARGS;
    }

    int result = HexSystemF(0, "cubectl config k3s namespace-delete %s", ns.c_str());
    if (result != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
k3sUserListMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="user_list" */) {
        return CLI_INVALID_ARGS;
    }

    if (HexSystemF(0, "cubectl config k3s user-list") != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
k3sUserGetMain(int argc, const char** argv)
{
    if (argc > 2 /* [1]="USERNAME" */) {
        return CLI_INVALID_ARGS;
    }

    int index;
    std::string username;
    if(CliMatchCmdHelper(argc, argv, 1, "cubectl config k3s user-list --no-header=true --no-namespace=true", &index, &username, "Select the user to get details") != CLI_SUCCESS) {
        return CLI_INVALID_ARGS;
    }

    if (HexSystemF(0, "cubectl config k3s user-get %s", username.c_str()) != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
k3sUserCreateMain(int argc, const char** argv)
{
    if (argc > 3 /* [1]="USERNAME", [2]="NAMESPACES" */) {
        return CLI_INVALID_ARGS;
    }

    std::string username, namespaces;
    if (!CliReadInputStr(argc, argv, 1, "Input name for new user: ", &username) || username.length() <= 0) {
        CliPrint("username is required");
        return CLI_INVALID_ARGS;
    }

    namespaces = cliSelectNamespacesToUser();
    int result = HexSystemF(0, "cubectl config k3s user-create %s --namespaces \"%s\"", username.c_str(), namespaces.c_str());
    if (result != 0) {
        CliPrintf("Failed to create k3s user(%s)", username.c_str());
        return CLI_FAILURE;
    };

    return CLI_SUCCESS;
}

static int
k3sUserUpdateMain(int argc, const char** argv)
{
    if (argc > 4 /* [1]="USERNAME", [2]="OPERATION", [3]="NAMESPACES" */) {
        return CLI_INVALID_ARGS;
    }

    int index;
    std::string username, operation, namespaces;
    if(CliMatchCmdHelper(argc, argv, 1, "cubectl config k3s user-list --no-header=true --no-namespace=true", &index, &username, "Select the user to update") != CLI_SUCCESS) {
        return CLI_INVALID_ARGS;
    }

    if(CliMatchCmdHelper(argc, argv, 2, "echo 'add\nremove'", &index, &operation, "Select the operator to operate namespace for user") != CLI_SUCCESS) {
        return CLI_INVALID_ARGS;
    }

    namespaces = cliSelectNamespacesToUser();
    int result = HexSystemF(0, "cubectl config k3s user-update %s --operation \"%s\" --namespaces \"%s\"", username.c_str(), operation.c_str(), namespaces.c_str());
    if (result != 0) {
        CliPrintf("Failed to update k3s user(%s)", username.c_str());
        return CLI_FAILURE;
    };

    return CLI_SUCCESS;
}

static int
k3sUserDeleteMain(int argc, const char** argv)
{
    if (argc > 2 /* [1]="USERNAME" */) {
        return CLI_INVALID_ARGS;
    }

    int index;
    std::string username;
    if(CliMatchCmdHelper(argc, argv, 1, "cubectl config k3s user-list --no-header=true --no-namespace=true", &index, &username, "Select the user to delete") != CLI_SUCCESS) {
        return CLI_INVALID_ARGS;
    }

    if (HexSystemF(0, "cubectl config k3s user-delete %s", username.c_str()) != 0) {
        return CLI_FAILURE;
    };

    return CLI_SUCCESS;
}

static int
k3sAdminExec(int argc, const char** argv)
{
    if (argc < 2 /* [1]="KUBECTL or HELM COMMAND" */) {
        return CLI_INVALID_ARGS;
    }

    std::string k3sCmd = joinArgv(argc, argv);
    if (HexSystemF(0, "cubectl config k3s admin-exec '%s'", k3sCmd.c_str()) != 0) {
        return CLI_FAILURE;
    };

    return CLI_SUCCESS;
}

static int
k3sEnableAdminDirectControl(int argc, const char** argv)
{
    if (argc > 2 /* [1]="TRUE or FALSE" */) {
        return CLI_INVALID_ARGS;
    }

    int index;
    std::string value;
    CliPrintf("Warning: Enabling K3S Admin Direct Control\nEnabling K3S Admin Direct Control grants you the ability to operate K3S with the highest level of administrative privileges. This means you will have control over all existing K3S resources, including both core system resources and user-created resources. This may result in unexpected issues with K3S core services, potentially impacting the core functionality of CubeCOS.\n\nBy enabling K3S Admin Direct Control, Bigstack assumes no responsibility for any consequences arising from subsequent actions. Please carefully consider whether you are certain about enabling K3S Admin Direct Control.\n\n");
    if (CliMatchCmdHelper(argc, argv, 1, "echo -e 'yes\nno'", &index, &value, "Enable K3S admin direct control:") != CLI_SUCCESS) {
        CliPrintf("Unknown action");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadConfirmation()) {
        return CLI_SUCCESS;
    }

    if (HexSystemF(0, "cubectl config k3s enable-admin-exec %s", value.c_str()) != 0) {
        return CLI_FAILURE;
    };

    return CLI_SUCCESS;
}

CLI_MODE(CLI_TOP_MODE, "k3s", "Work with K3S.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("k3s", "resource_overview_list", k3sGetResourceOverviewMain, NULL,
                 "Get K3S resource overview like capacity, allocated, and available.",
                 "resource_overview_list");

CLI_MODE_COMMAND("k3s", "namespace_list", k3sNamespaceListMain, NULL,
                 "List K3S namespaces with resource quota.",
                 "namespace_list");

CLI_MODE_COMMAND("k3s", "namespace_create", k3sNamespaceCreateMain, NULL,
                 "Create a K3S namespace with resource quota.",
                 "namespace_create [namespace] [cpu quota] [memory quota] [storage quota]");

CLI_MODE_COMMAND("k3s", "namespace_update", k3sNamespaceUpdateMain, NULL,
                 "Update a K3S namespace with resource quota.",
                 "namespace_update [namespace] [cpu quota] [memory quota] [storage quota]");

CLI_MODE_COMMAND("k3s", "namespace_delete", k3sNamespaceDeleteMain, NULL,
                 "Delete a K3S namespace.",
                 "namespace_delete [namespace]");

CLI_MODE_COMMAND("k3s", "user_list", k3sUserListMain, NULL,
                 "List K3S users with access namespaces.",
                 "user_list");

CLI_MODE_COMMAND("k3s", "user_get", k3sUserGetMain, NULL,
                 "Get K3S user details like access namespace and the url of kube config.",
                 "user_get [username]");

CLI_MODE_COMMAND("k3s", "user_create", k3sUserCreateMain, NULL,
                 "Create a K3S user with access to namespaces.",
                 "user_create [username]");

CLI_MODE_COMMAND("k3s", "user_update", k3sUserUpdateMain, NULL,
                 "Update a K3S user with access to namespaces.",
                 "user_update [username]");

CLI_MODE_COMMAND("k3s", "user_delete", k3sUserDeleteMain, NULL,
                 "Delete a K3S user.",
                 "user_delete [username]");

CLI_MODE_COMMAND("k3s", "admin_exec", k3sAdminExec, NULL,
                 "Direct control for K3S via native kubectl or helm. Please call enable_admin_exec to enable first.",
                 "admin_exec [kubectl or helm command]");

CLI_MODE_COMMAND("k3s", "enable_admin_exec", k3sEnableAdminDirectControl, NULL,
                 "Enable direct control for K3S. Please read the warning message before enabling.",
                 "enable_admin_exec [yes or no]");
