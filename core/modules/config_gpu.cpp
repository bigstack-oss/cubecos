// CUBE SDK

#include <cstring>
#include <fstream>
#include <sstream>
#include <unistd.h>
#include <hex/log.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/config_module.h>
#include <hex/dryrun.h>
#include <hex/tempfile.h>
#include <third_party/json11.hpp>

static const char GPU_CONFIG_DIR[]  = "/etc/cube/cos/gpu";
static const char GPU_CONFIG_FILE[] = "/etc/cube/cos/gpu/config.json";

// Looks up GPU gpuId via gpu_device_list, the single source of truth for
// GPU id/name/type/pciAddress - it already unions live nvidia-smi data with
// `config.json` entries, specifically for GPUs no longer visible to nvidia-smi
// after bound to vfio-pci.
// Returns json11::Json() (null) if the command fails or the GPU isn't found.
static json11::Json
FindGpuDevice(const char* gpuId)
{
    const std::string deviceListJson = HexUtilPOpen(HEX_SDK " gpu_device_list");

    std::string jsonError;
    const json11::Json deviceList = json11::Json::parse(deviceListJson, jsonError);

    if (!jsonError.empty()) {
        return json11::Json();
    }

    for (const json11::Json& entry : deviceList.array_items()) {
        if (entry["id"].is_string() && entry["id"].string_value() == gpuId) {
            return entry;
        }
    }

    return json11::Json();
}

static void
ResourceSetUsage(void)
{
    fprintf(stderr, "Usage: %s gpu_resource_set <gpu_id> <new_type> [profiles]\n", HexLogProgramName());
}

static int
ResourceSetMain(int argc, char* argv[])
{
    /*
     * [0]="gpu_resource_set", [1]=<gpu_id>, [2]=<new_type>, [3]=[profiles]
     */
    if (argc < 3 || argc > 4) {
        HexLogError("gpu_resource_set: invalid number of arguments");
        ResourceSetUsage();
        return EXIT_FAILURE;
    }

    const char* gpuId   = argv[1];
    const char* newType  = argv[2];
    const char* profiles = (argc == 4) ? argv[3] : "";

    if (strcmp(newType, "pgpu") != 0 &&
        strcmp(newType, "sriovVgpu") != 0 &&
        strcmp(newType, "migBackedVgpu") != 0) {
        HexLogError("gpu_resource_set: invalid type '%s'. Must be one of: pgpu, sriovVgpu, migBackedVgpu", newType);
        return EXIT_FAILURE;
    }

    if (strcmp(newType, "pgpu") == 0 && profiles[0] != '\0') {
        HexLogError("gpu_resource_set: profiles is not allowed when new_type is pgpu");
        return EXIT_FAILURE;
    }

    if (
        (strcmp(newType, "sriovVgpu") == 0 || strcmp(newType, "migBackedVgpu") == 0) &&
        profiles[0] == '\0'
    ) {
        HexLogError("gpu_resource_set: profiles is required when new_type is sriovVgpu or migBackedVgpu");
        return EXIT_FAILURE;
    }

    if (access(GPU_CONFIG_FILE, F_OK) != 0) {
        HexLogError("gpu_resource_set: GPU config file not found at %s", GPU_CONFIG_FILE);
        return EXIT_FAILURE;
    }

    if (HexUtilSystemF(0, 0, HEX_SDK " gpu_resource_set_check %s %s %s", gpuId, newType, profiles) != 0) {
        HexLogError("gpu_resource_set: pre-condition check failed for GPU %s", gpuId);
        return EXIT_FAILURE;
    }

    // Existence already confirmed by gpu_resource_set_validate above; this
    // is purely to fetch name/pciAddress for binding and persisting.
    const json11::Json device = FindGpuDevice(gpuId);
    if (!device.is_object()) {
        HexLogError("gpu_resource_set: GPU %s not found", gpuId);
        return EXIT_FAILURE;
    }

    const std::string name = device["name"].is_string() ? device["name"].string_value() : "";
    const std::string pciAddress = device["pciAddress"].is_string() ? device["pciAddress"].string_value() : "";
    if (name.empty() || pciAddress.empty()) {
        HexLogError("gpu_resource_set: GPU %s is missing name/pciAddress in the config file", gpuId);
        return EXIT_FAILURE;
    }

    if (HexUtilSystemF(0, 0, HEX_SDK " gpu_unset_current_type %s", gpuId) != 0) {
        HexLogError("gpu_resource_set: failed to unset current type for GPU %s", gpuId);
        return EXIT_FAILURE;
    }

    if (strcmp(newType, "pgpu") == 0) {
        if (HexUtilSystemF(0, 0, HEX_SDK " gpu_bind_vfio_pci %s", pciAddress.c_str()) != 0) {
            HexLogError("gpu_resource_set: failed to bind GPU %s to vfio-pci for passthrough", gpuId);
            return EXIT_FAILURE;
        }

        HexTempFile tmpFile;
        if (tmpFile.fd() < 0) {
            HexLogError("gpu_resource_set: failed to create a temporary file");
            return EXIT_FAILURE;
        }
        tmpFile.close();

        if (HexUtilSystemF(0, 0,
                "jq -c --arg id \"%s\" --arg name \"%s\" --arg pciAddress \"%s\" "
                "'map(select(.id != $id)) + [{id:$id, name:$name, type:\"pgpu\", pciAddress:$pciAddress, profiles:null}]' %s > %s",
                gpuId, name.c_str(), pciAddress.c_str(), GPU_CONFIG_FILE, tmpFile.path()) != 0) {
            HexLogError("gpu_resource_set: failed to build updated GPU config for %s", gpuId);
            return EXIT_FAILURE;
        }

        if (HexUtilSystemF(0, 0, "mv %s %s", tmpFile.path(), GPU_CONFIG_FILE) != 0) {
            HexLogError("gpu_resource_set: failed to persist GPU %s config", gpuId);
            return EXIT_FAILURE;
        }

        HexLogInfo("gpu_resource_set: successfully updated GPU %s to pgpu", gpuId);
        return EXIT_SUCCESS;
    } else if (strcmp(newType, "sriovVgpu") == 0) {
        // TODO
    } else if (strcmp(newType, "migBackedVgpu") == 0) {
        // TODO
    }

    HexLogError("gpu_resource_set: unhandled type %s", newType);
    return EXIT_FAILURE;
}

static bool
Commit(bool modified, int dryLevel)
{
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (HexMakeDir(GPU_CONFIG_DIR, "root", "root", 0755) != 0) {
        HexLogError("Failed to create GPU config directory: %s", GPU_CONFIG_DIR);
        return false;
    }

    if (access(GPU_CONFIG_FILE, F_OK) != 0) {
        /* Data in `config.json` is an array with the following data structure:
        {
          id: string
          name: string
          type: 'pgpu' | 'sriovVgpu' | 'migBackedVgpu'
          pciAddress: string
          profiles: {
            id: number
            count: number
            alias: string
          }[] | null
        }
        */
        HexUtilSystemF(0, 0, "echo '[]' > %s", GPU_CONFIG_FILE);
        return true;
    }

    // Hardware driver bindings (e.g. vfio-pci passthrough) do not survive a
    // reboot or an OS upgrade on their own, but Commit() runs on every boot
    // (via bootstrap) and every settings commit, so re-apply persisted
    // policy here rather than relying on static modprobe.d config.
    std::ifstream configStream(GPU_CONFIG_FILE);
    std::stringstream buffer;
    buffer << configStream.rdbuf();

    std::string jsonError;
    const json11::Json gpuConfig = json11::Json::parse(buffer.str(), jsonError);
    if (!jsonError.empty()) {
        HexLogError("Failed to parse GPU config file %s: %s", GPU_CONFIG_FILE, jsonError.c_str());
        return false;
    }

    for (const json11::Json& entry : gpuConfig.array_items()) {
        if (!entry["id"].is_string() || !entry["type"].is_string()) {
            continue;
        }

        const std::string id = entry["id"].string_value();
        const std::string type = entry["type"].string_value();

        if (type == "pgpu") {
            if (!entry["pciAddress"].is_string() || entry["pciAddress"].string_value().empty()) {
                HexLogError("GPU %s has type pgpu but no recorded pciAddress; cannot re-apply binding", id.c_str());
                return false;
            }

            const std::string pciAddress = entry["pciAddress"].string_value();

            // Re-apply by PCI bus address, not by GPU UUID: once a GPU is
            // bound to vfio-pci it is no longer enumerable by nvidia-smi,
            // so a UUID-based lookup would fail here on every Commit() run
            // after the first.
            if (HexUtilSystemF(0, 0, HEX_SDK " gpu_bind_vfio_pci %s", pciAddress.c_str()) != 0) {
                HexLogError("Failed to re-apply pgpu passthrough binding for GPU %s", id.c_str());
                return false;
            }
        }
        // TODO: re-apply sriovVgpu / migBackedVgpu once gpu_resource_set supports them.
    }

    return true;
}

CONFIG_MODULE(gpu, 0, 0, 0, 0, Commit);

CONFIG_MIGRATE(gpu, GPU_CONFIG_DIR);

CONFIG_COMMAND(gpu_resource_set, ResourceSetMain, ResourceSetUsage);
