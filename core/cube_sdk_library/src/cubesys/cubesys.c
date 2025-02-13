// HEX SDK

#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include <hex/log.h>
#include <hex/process.h>
#include <hex/strict.h>
#include <cube/cubesys.h>

#define HEX_DONE "/run/bootstrap_done"
#define CUBE_DONE "/run/cube_commit_done"

int
CubeSysCommitAll(void)
{
    return access(CUBE_DONE, F_OK) == 0 ? 1 : 0;
}

int
CubeBootLevel(void)
{
    if (access(HEX_DONE, F_OK) == 0) {
        if (access(CUBE_DONE, F_OK) == 0)
            return BLVL_DONE;
        else
            return BLVL_STD;
    }
    else
        return BLVL_BS;
}

int
CubeHasRole(int role)
{
    if ((role & R_CONTROL) && HexSystemF(0, HEX_SDK " is_control_node") == 0)
        return 1;
    if ((role & R_COMPUTE) && HexSystemF(0, HEX_SDK " is_compute_node") == 0)
        return 1;
    if ((role & R_STORAGE) && HexSystemF(0, HEX_SDK " is_storage_node") == 0)
        return 1;
    if ((role & R_CTRL_NOT_EDGE) && HexSystemF(0, HEX_SDK " is_control_node") == 0 && HexSystemF(0, HEX_SDK " is_edge_node") != 0)
        return 1;
    if ((role & R_CORE) && HexSystemF(0, HEX_SDK " is_core_node") == 0)
        return 1;

    return 0;
}

