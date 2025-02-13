// HEX SDK

#include <hex/process.h>
#include <hex/log.h>
#include <hex/strict.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

static int
GpuStatusMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="status" */)
        return CLI_INVALID_ARGS;

    HexSpawn(0, HEX_SDK, "gpu_device_status", NULL);

    return CLI_SUCCESS;
}

static int
GpuTypeListMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="supported_type_list" */)
        return CLI_INVALID_ARGS;

    HexSystemF(0, HEX_SDK " -v gpu_supported_type_list");

    return CLI_SUCCESS;
}

static int
GpuVfEnableMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="virtual_function_enable" */)
        return CLI_INVALID_ARGS;

    HexSystemF(0, HEX_SDK " gpu_vf_enable");
    CliPrintf("\nGPU IOMMU Group List");
    HexSystemF(0, HEX_SDK " -v gpu_iommu_list");

    return CLI_SUCCESS;
}

static int
GpuVfDisableMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="virtual_function_disable" */)
        return CLI_INVALID_ARGS;

    HexSystemF(0, HEX_SDK " gpu_vf_disable");
    CliPrintf("\nGPU IOMMU Group List");
    HexSystemF(0, HEX_SDK " -v gpu_iommu_list");

    return CLI_SUCCESS;
}

static int
GpuCreateDpMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="create_device_profile", [1]=<unit> */)
        return CLI_INVALID_ARGS;

    if (argc == 1) {
        HexSystemF(0, HEX_SDK " os_device_profile_create");
    }
    else {
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

CLI_MODE_COMMAND("gpu", "supported_type_list", GpuTypeListMain, NULL,
    "List supported GPU types instances could get.",
    "supported_type_list");

CLI_MODE_COMMAND("gpu", "virtual_function_enable", GpuVfEnableMain, NULL,
    "Enable GPU virtual function for this node.",
    "virtual_function_enable");

CLI_MODE_COMMAND("gpu", "virtual_function_disable", GpuVfDisableMain, NULL,
    "Disable GPU virtual function for this node.",
    "virtual_function_disable");

CLI_MODE_COMMAND("gpu", "device_profile_create", GpuCreateDpMain, NULL,
    "Create device profile for all GPU devices by giving unit or 1 if unit is absent.",
    "device_profile_create [unit]");

CLI_MODE_COMMAND("gpu", "device_profile_delete", GpuDeleteDpMain, NULL,
    "Delete device profile of the giving name.",
    "device_profile_delete [name]");

