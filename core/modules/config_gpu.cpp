// CUBE SDK

#include <unistd.h>
#include <hex/log.h>
#include <hex/filesystem.h>
#include <hex/process_util.h>
#include <hex/config_module.h>
#include <hex/dryrun.h>

static const char GPU_CONFIG_DIR[]  = "/etc/cube/cos/gpu";
static const char GPU_CONFIG_FILE[] = "/etc/cube/cos/gpu/config.json";

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
          type: 'pgpu' | 'sriovVgpu' | 'migBackedVgpu'
          profiles: {
            id: number
            count: number
            alias: string
          }[] | null
        }
        */
        HexUtilSystemF(0, 0, "echo '[]' > %s", GPU_CONFIG_FILE);
    }

    return true;
}

CONFIG_MODULE(gpu, 0, 0, 0, 0, Commit);

CONFIG_MIGRATE(gpu, GPU_CONFIG_DIR);
