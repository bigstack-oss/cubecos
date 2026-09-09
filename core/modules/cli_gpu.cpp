// CUBE SDK

#include <hex/cli_module.h>
#include <hex/cli_util.h>
#include <hex/exec.hpp>
#include <hex/log.h>
#include <hex/process.h>
#include <hex/strict.h>

static int
GpuStatusMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="status" */)
        return CLI_INVALID_ARGS;

    HexSpawn(0, HEX_SDK, "gpu_device_status", NULL);

    return CLI_SUCCESS;
}

static int
GpuCreateDpMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="create_device_profile", [1]=<unit> */)
        return CLI_INVALID_ARGS;

    if (argc == 1) {
        HexSystemF(0, HEX_SDK " os_device_profile_create");
    } else {
        HexSystemF(0, HEX_SDK " os_device_profile_create %s", argv[1]);
    }

    return CLI_SUCCESS;
}

static int
GpuDeleteDpMain(int argc, const char** argv)
{
    if (argc != 2 /* [0]="delete_device_profile", [1]=<name> */)
        return CLI_INVALID_ARGS;

    HexSystemF(0, HEX_SDK " os_device_profile_delete %s", argv[1]);

    return CLI_SUCCESS;
}

static int
GpuResourceListMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="resource_list" */)
        return CLI_INVALID_ARGS;

    HexSpawn(0, HEX_SDK, "gpu_resource_summary", NULL);

    return CLI_SUCCESS;
}

static int
GpuProfileListMain(int argc, const char** argv)
{
    /*
     * [0]="profile_list", [1]=<gpu uuid>
     */
    if (argc > 2)
        return CLI_INVALID_ARGS;

    std::string uuid;
    int index;

    std::string optCmd = HEX_SDK " gpu_device_uuid_list";
    std::string descCmd = HEX_SDK " -v gpu_device_uuid_list";

    if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &uuid,
                              "Select a GPU card: ") != CLI_SUCCESS) {
        CliPrintf("GPU card is missing or not found");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "gpu_vgpu_profile_summary", uuid.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
GpuResourceSetMain(int argc, const char** argv)
{
    /*
     * [0]="resource_set", [1]=<gpu uuid>, [2]=<resource type>, [3]=<profiles>
     */
    if (argc > 4)
        return CLI_INVALID_ARGS;

    std::string uuid, type;
    int index;

    std::string optCmd = HEX_SDK " gpu_device_uuid_list";
    std::string descCmd = HEX_SDK " -v gpu_device_uuid_list";

    if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &uuid,
                              "Select a GPU card: ") != CLI_SUCCESS) {
        CliPrintf("GPU card is missing or not found");
        return CLI_INVALID_ARGS;
    }

    CliList types;
    types.push_back("pgpu");
    types.push_back("sriovVgpu");
    types.push_back("migBackedVgpu");

    if (CliMatchListHelper(argc, argv, 2, types, &index, &type) != 0) {
        CliPrintf("resource type is missing or not found");
        return CLI_INVALID_ARGS;
    }

    /*
     * profiles is a JSON array of {id, count}, required by the two vGPU types
     * and omitted for pgpu. It is passed through untouched: every rule about
     * what a valid carve is - the card's own supported types, the profile ids,
     * the total VRAM - is enforced fail-closed inside hex_config's
     * gpu_resource_set, after it has released the card from vfio-pci. Checking
     * any of it a second time here would run before that release, i.e. at the
     * one point in the sequence where the answer cannot be read.
     *
     * HexSpawn is execv-based, so the JSON crosses as one argv element and
     * never meets a shell. Its stdout and stderr go straight to the terminal:
     * a carve takes 25-60s and reports as it goes, and a rejection has to say
     * why rather than leaving the operator with a bare exit code.
     */
    std::string profiles;
    if (argc == 4) {
        profiles = argv[3];
    }
    else if (type != "pgpu") {
        /*
         * Both vGPU types require profiles, so an interactive run that stopped
         * after the type would be able to set nothing but pgpu. Print what the
         * card offers first - the ids are vGPU type ids, not something an
         * operator can be expected to produce from memory.
         */
        CliPrintf("\nvGPU profiles available on this card:");
        HexSpawn(0, HEX_SDK, "gpu_vgpu_profile_summary", uuid.c_str(), NULL);

        if (!CliReadInputStr(argc, argv, 3,
                             "Profiles as a JSON array of {id, count}: ",
                             &profiles) || profiles.length() == 0) {
            CliPrintf("profiles are required for %s", type.c_str());
            return CLI_INVALID_ARGS;
        }
    }

    /*
     * -e makes hex_config log to stderr as well as syslog. Without it
     * gpu_resource_set exits 1 with nothing on stdout or stderr - measured on
     * cn13 - and the operator is left with hex_cli's bare "command failure"
     * while the actual reason ("profiles must be a non-empty JSON array of
     * { id, count } objects") sits in /var/log/hex_config.log. HexSpawn passes
     * stderr straight through, so this one flag is what makes a refusal
     * explain itself. The same flag is what cube-cos-api needs to stop
     * answering 500 "exit status 1" (#1452).
     */
    int ret;
    if (!profiles.empty()) {
        ret = HexSpawn(0, HEX_CFG, "-e", "gpu_resource_set",
                       uuid.c_str(), type.c_str(), profiles.c_str(), NULL);
    } else {
        ret = HexSpawn(0, HEX_CFG, "-e", "gpu_resource_set",
                       uuid.c_str(), type.c_str(), NULL);
    }

    if (ret != 0)
        return CLI_FAILURE;

    return CLI_SUCCESS;
}

CLI_MODE(CLI_TOP_MODE, "gpu",
    "Work with GPU settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired());

CLI_MODE_COMMAND("gpu", "status", GpuStatusMain, NULL,
    "Show GPU and virtual GPU status.",
    "status");

CLI_MODE_COMMAND("gpu", "resource_list", GpuResourceListMain, NULL,
    "List the GPU resources of this node and their resource types.",
    "resource_list");

CLI_MODE_COMMAND("gpu", "profile_list", GpuProfileListMain, NULL,
    "List the vGPU profiles a GPU card supports.",
    "profile_list [<gpu uuid>]");

CLI_MODE_COMMAND("gpu", "resource_set", GpuResourceSetMain, NULL,
    "Set the resource type of a GPU card.",
    "resource_set [<gpu uuid>] [<pgpu|sriovVgpu|migBackedVgpu>] [<profiles>]");

CLI_MODE_COMMAND("gpu", "device_profile_create", GpuCreateDpMain, NULL,
    "Create device profile for all GPU devices by giving unit or 1 if unit is absent.",
    "device_profile_create [unit]");

CLI_MODE_COMMAND("gpu", "device_profile_delete", GpuDeleteDpMain, NULL,
    "Delete device profile of the giving name.",
    "device_profile_delete [name]");

static int
GpuEnableNvlinkMain(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    const ExecSyncResult r = ExecBashSync(
        0,
        false,
        true,
        {},
        "systemctl start nvidia-fabricmanager");
    if (r.exitCode != 0) {
        printf("%s", r.stderrOutput.c_str());
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

CLI_MODE_COMMAND("gpu", "nvlink_enable", GpuEnableNvlinkMain, NULL,
    "Start nvidia-fabricmanager to manage NVLink devices.",
    "nvlink_enable");

static int
GpuDisableNvlinkMain(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    const ExecSyncResult r = ExecBashSync(
        0,
        false,
        true,
        {},
        "systemctl stop nvidia-fabricmanager");
    if (r.exitCode != 0) {
        printf("%s", r.stderrOutput.c_str());
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

CLI_MODE_COMMAND("gpu", "nvlink_disable", GpuDisableNvlinkMain, NULL,
    "Stop nvidia-fabricmanager to no longer manage NVLink devices.",
    "nvlink_disable");
