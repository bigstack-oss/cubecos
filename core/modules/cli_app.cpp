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

static const char* HINT_INPUT_PUBLIC_NET = "Input public net for the framework(e.g. 'public' and so on): ";
static const char* HINT_INPUT_MGMT_NET = "Input management net for the framework(e.g. 'public' or 'mgmt' and so on): ";
static const char* HINT_INPUT_LB_IP = "Input load balancer ip for the framework(should be an ip address in the range of public net): ";
static const char* HINT_INPUT_OS_IMAGE = "Input os image for the framework(default is rancher-cluster-image-rke2-v1.32.4.raw): ";

static int
appRegisterMain(int argc, const char** argv)
{
    if (argc == 1 || argc > 4  /* [1]="app.pigz", [2]="app framework name", [3]="skip_flavor"  */) {
        return CLI_INVALID_ARGS;
    }
    int ret;
    std::string app_path = argv[1];
    std::string app_fw_name = argv[2];
    CliPrintf("installing app: %s...", app_path.c_str());

    if(argc == 4){
        std::string skip_flag = argv[3];
        ret = HexSpawn(0, HEX_SDK, "app_import", app_path.c_str(), app_fw_name.c_str(), skip_flag.c_str(), NULL);
    } else {
        ret = HexSpawn(0, HEX_SDK, "app_import", app_path.c_str(), app_fw_name.c_str(), NULL);
    }

    if (ret != 0)
        CliPrintf("app failed to install");
    else {
        CliPrintf("app installed successfully");
    }

    return CLI_SUCCESS;
}

static int
appProjectCreateMain(int argc, const char** argv)
{
    if (argc != 4 /* [1]="PROJ_NAME",[2]="MGMT_NETWORK",[3]="PUB_NETWORK"*/) {
        return CLI_INVALID_ARGS;
    }

    std::string name = argv[1];
    std::string mgmtMet = argv[2];
    std::string pubNet = argv[3];

    int result = HexSystemF(0, "appctl create project --name=%s --net.public=%s --net.mgmt=%s", name.c_str(), pubNet.c_str(), mgmtMet.c_str());
    if (result != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
appProjectDeleteMain(int argc, const char** argv)
{
    if (argc != 2 /* [1]="PROJ_NAME"*/) {
        return CLI_INVALID_ARGS;
    }

    std::string name = argv[1];

    CliPrintf("confirm to delete app project.");
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    int result = HexSystemF(0, "appctl delete project --name=%s", name.c_str());
    if (result != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}


static int
frameworkCheckPrerequisitesMain(int argc, const char** argv)
{
    int result = HexSystemF(0, "appctl check framework prerequisites");
    if (result != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
frameworkCheckPortAccessMain(int argc, const char** argv)
{
    if (argc > 2 /* [1]="FRAMEWORK NAME" */) {
        return CLI_INVALID_ARGS;
    }

    std::string name;
    if (!CliReadInputStr(argc, argv, 1, "Input framework name for port check: ", &name) || name.length() <= 0) {
        CliPrint("framework name is required");
        return CLI_INVALID_ARGS;
    }

    int result = HexSystemF(0, "appctl check framework portAccess --name=%s", name.c_str());
    if (result != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
frameworkCreateMain(int argc, const char** argv)
{
    if (argc > 6 /* [1]="FRAMEWORK NAME", [2]="PUBLIC NET", [3]="MANAGEMENT NET", [4]="LOAD BALANCER IP", [5]="OS IMAGE" */) {
        return CLI_INVALID_ARGS;
    }

    std::string name, publicNet, mgmtNet, loadBalancerIp, osImage;
    if (!CliReadInputStr(argc, argv, 1, "Input name for new framework: ", &name) || name.length() <= 0) {
        CliPrint("framework name is required");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 2, HINT_INPUT_PUBLIC_NET, &publicNet) || publicNet.length() <= 0) {
        CliPrint("public net is required");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 3, HINT_INPUT_MGMT_NET, &mgmtNet) || mgmtNet.length() <= 0) {
        CliPrint("management net is required");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 4, HINT_INPUT_LB_IP, &loadBalancerIp) || loadBalancerIp.length() <= 0) {
        CliPrint("load balancer ip is required");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 5, HINT_INPUT_OS_IMAGE, &osImage) || osImage.length() <= 0) {
        CliPrint("os image is required");
        return CLI_INVALID_ARGS;
    }

    int result = HexSystemF(0, "appctl create framework --name=%s --net.public=%s --net.mgmt=%s --net.loadbalancer.ip=%s --os.image=%s", name.c_str(), publicNet.c_str(), mgmtNet.c_str(), loadBalancerIp.c_str(), osImage.c_str());
    if (result != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
frameworkListMain(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    if (HexSystemF(0, "appctl list framework --welcome=false") != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
frameworkDeleteMain(int argc, const char** argv)
{
    if (argc > 2 /* [1]="FRAMEWORK NAME" */) {
        return CLI_INVALID_ARGS;
    }

    std::string name;
    if (!CliReadInputStr(argc, argv, 1, "Input name to delete framework: ", &name) || name.length() <= 0) {
        CliPrint("framework name is required");
        return CLI_INVALID_ARGS;
    }

    int result = HexSystemF(0, "appctl delete framework --name=%s", name.c_str());
    if (result != 0) {
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

CLI_MODE(CLI_TOP_MODE, "app", "Work with applications.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("app", "app_register", appRegisterMain, NULL,
                 "Install app.",
                 "app_install app.pigz");

CLI_MODE_COMMAND("app", "framework_check_prerequisites", frameworkCheckPrerequisitesMain, NULL,
                 "Check app-framework prerequisites.",
                 "framework_check_prerequisites");

CLI_MODE_COMMAND("app", "framework_check_port_access", frameworkCheckPortAccessMain, NULL,
                 "Check app-framework port access.",
                 "framework_check_port_access");

CLI_MODE_COMMAND("app", "framework_create", frameworkCreateMain, NULL,
                 "Create app-framework.",
                 "framework_create FRAMEWORK_NAME PUBLIC_NET MANAGEMENT_NET LOAD_BALANCER_IP OS_IMAGE");

CLI_MODE_COMMAND("app", "framework_list", frameworkListMain, NULL,
                 "List app-framework.",
                 "framework_list");

CLI_MODE_COMMAND("app", "framework_delete", frameworkDeleteMain, NULL,
                 "Delete app-framework.",
                 "framework_delete FRAMEWORK_NAME");

CLI_MODE_COMMAND("app", "project_create", appProjectCreateMain, NULL,
                 "Create app project.",
                 "project_create PROJ_NAME MGMT_NET PUB_NET");

CLI_MODE_COMMAND("app", "project_delete", appProjectDeleteMain, NULL,
                 "Delete app project.",
                 "project_delete PROJ_NAME");
