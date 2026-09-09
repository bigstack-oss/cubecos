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

CLI_MODE(CLI_TOP_MODE, "gpu",
    "Work with GPU settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired());

CLI_MODE_COMMAND("gpu", "status", GpuStatusMain, NULL,
    "Show GPU and virtual GPU status.",
    "status");

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
