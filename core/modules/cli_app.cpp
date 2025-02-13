// CUBE SDK

#include <sys/stat.h>

#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/log.h>
#include <hex/strict.h>
#include <hex/parse.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

#include <cube/cubesys.h>

static int
frameworkInstallMain(int argc, const char** argv)
{
    if (argc != 4 /* [1]="MGMT_NETWORK", [2]="PUB_NETWORK", [3]="LB_IP" */) {
        return CLI_INVALID_ARGS;
    }

    std::string mgmt_net = argv[1];
    std::string pub_net = argv[2];
    std::string lb_ip = argv[3];

    CliPrintf("installing app-framework...");
    if (HexSpawn(0, HEX_SDK, "app_framework_install", mgmt_net.c_str(), pub_net.c_str(), lb_ip.c_str(), NULL) != 0)
        CliPrintf("preconditions: extpack and mgmt/pub networks on admin project");
    else {
        CliPrintf("app-framework installed successfully");
    }

    return CLI_SUCCESS;
}

static int
frameworkUninstallMain(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    CliPrintf("Uninstall app-framework will also destroy all apps running on top of it.");
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    CliPrintf("uninstalling app-framework...");
    if (HexSpawn(0, HEX_SDK, "app_framework_uninstall", NULL) != 0)
        CliPrintf("app-framework failed to uninstall");
    else {
        CliPrintf("app-framework uninstalled successfully");
    }

    return CLI_SUCCESS;
}

static int
appInstallMain(int argc, const char** argv)
{
    if (argc == 1 || argc > 3  /* [1]="app.pigz", [2]="skip_flavor"  */) {
        return CLI_INVALID_ARGS;
    }
    int ret;
    std::string app_path = argv[1];

    CliPrintf("installing app: %s...", app_path.c_str());

    if(argc == 3){
        std::string skip_flag = argv[2];
        ret = HexSpawn(0, HEX_SDK, "app_import", app_path.c_str(), skip_flag.c_str(), NULL);
    } else {
        ret = HexSpawn(0, HEX_SDK, "app_import", app_path.c_str(), NULL);
    }

    if (ret != 0)
        CliPrintf("app failed to install");
    else {
        CliPrintf("app installed successfully");
    }

    return CLI_SUCCESS;
}

static int
appUninstallMain(int argc, const char** argv)
{
    if (argc != 2 /* [1]="app.pigz"*/) {
        return CLI_INVALID_ARGS;
    }

    std::string app_path = argv[1];

    CliPrintf("confirm to uninstall specified app.");
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    CliPrintf("uninstalling app: %s...", app_path.c_str());
    if (HexSpawn(0, HEX_SDK, "app_deploy uninstall", app_path.c_str(), NULL) != 0)
        CliPrintf("app failed to uninstall");
    else {
        CliPrintf("app uninstalled successfully");
    }

    return CLI_SUCCESS;
}

static int
appProjectCreateMain(int argc, const char** argv)
{
    if (argc != 4 /* [1]="PROJ_NAME",[2]="MGMT_NETWORK",[3]="PUB_NETWORK"*/) {
        return CLI_INVALID_ARGS;
    }

    std::string proj_name = argv[1];
    std::string mgmt_net = argv[2];
    std::string pub_net = argv[3];

    CliPrintf("creating app project: %s...", proj_name.c_str());
    if (HexSpawn(0, HEX_SDK, "app_project_create", proj_name.c_str(), mgmt_net.c_str(), pub_net.c_str(), NULL) != 0)
        CliPrintf("app project failed to create");
    else {
        CliPrintf("app project created successfully");
    }

    return CLI_SUCCESS;
}

static int
appProjectDeleteMain(int argc, const char** argv)
{
    if (argc != 2 /* [1]="PROJ_NAME"*/) {
        return CLI_INVALID_ARGS;
    }

    std::string proj_name = argv[1];

    CliPrintf("confirm to delete app project.");
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    CliPrintf("deleting app project: %s...", proj_name.c_str());
    if (HexSpawn(0, HEX_SDK, "app_project_delete", proj_name.c_str(), NULL) != 0)
        CliPrintf("app project failed to delete");
    else {
        CliPrintf("app project deleted successfully");
    }

    return CLI_SUCCESS;
}


CLI_MODE(CLI_TOP_MODE, "app", "Work with applications.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("app", "framework_install", frameworkInstallMain, NULL,
                 "Install app-framework.",
                 "framework_install MGMT_NETWORK PUB_NETWORK LOADBALANCER_IP");

CLI_MODE_COMMAND("app", "framework_uninstall", frameworkUninstallMain, NULL,
                 "Uninstall app-framework.",
                 "framework_uninstall");

CLI_MODE_COMMAND("app", "app_install", appInstallMain, NULL,
                 "Install app.",
                 "app_install app.pigz");

CLI_MODE_COMMAND("app", "app_uninstall", appUninstallMain, NULL,
                 "Uninstall app.",
                 "app_uninstall app.pigz");

CLI_MODE_COMMAND("app", "project_create", appProjectCreateMain, NULL,
                 "Create app project.",
                 "project_create PROJ_NAME MGMT_NET PUB_NET");

CLI_MODE_COMMAND("app", "project_delete", appProjectDeleteMain, NULL,
                 "Delete app project.",
                 "project_delete PROJ_NAME");

