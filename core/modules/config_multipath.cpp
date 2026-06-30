// CUBE SDK

#include <unistd.h>

#include <hex/log.h>
#include <hex/process_util.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/dryrun.h>

#include <cube/systemd_util.h>

#include "include/role_cubesys.h"

static const char NAME[]           = "multipathd";
static const char MULTIPATH_CONF[] = "/etc/multipath.conf";

static bool s_bCubeModified = false;
static bool s_bStorageBackendModified = false;

static CubeRole_e s_eCubeRole;

// using external tunings (node role + cinder's external-storage backends)
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CINDER_STORAGE_BACKEND);

// parse tunings
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR_ARRAY(s_storageBackends, CINDER_STORAGE_BACKEND, 2);

// Dedicated owner of multipathd's lifecycle on a running node. The matching rootfs
// files -- base /etc/multipath.conf (with the global overrides{}), the per-backend
// /etc/multipath/conf.d, and the device-mapper-multipath package -- are populated
// by core/multipath/multipath.mk.
//
// No config-module prerequisites (the HBA and IP network are up before the
// config-commit phase), so hex_config orders it at its earliest slot -- ahead of
// every SAN consumer -- so the overrides{} (no_path_retry fail / fast_io_fail /
// san_path_err) are loaded before anything touches a SAN device; otherwise a
// down/flapping SAN map under the built-in no_path_retry=queue hangs OSD partition
// enumeration or a cinder attach in uninterruptible D-state.

static bool
Init()
{
    // Fail-safe: create a base config if the rootfs somehow didn't ship one.
    if (access(MULTIPATH_CONF, F_OK) != 0) {
        HexUtilSystemF(0, 0, "/usr/sbin/mpathconf --enable");
    }
    return true;
}

static bool
ParseCube(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 1);
    return true;
}

static void
NotifyCube(bool modified)
{
    s_bCubeModified = IsModifiedTune(1);
    s_eCubeRole = GetCubeRole(s_cubeRole);
}

static bool
ParseCinder(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 2);
    return true;
}

static void
NotifyCinder(bool modified)
{
    // True when an operator adds/removes an external storage backend -- the same
    // predicate config_cinder uses -- which rewrites the per-backend conf.d.
    s_bStorageBackendModified = s_storageBackends.modified();
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    // First-time setup / boot always applies. Otherwise only re-touch multipathd
    // when something relevant changed -- this module's tunings, the node role, or
    // the cinder external-storage backends -- so an unrelated tuning change or
    // policy commit does NOT reconfigure/restart it.
    if (IsBootstrap())
        return true;

    return modified | s_bCubeModified | s_bStorageBackendModified;
}

static bool
Commit(bool modified, int dryLevel)
{
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (!CommitCheck(modified, dryLevel))
        return true;

    // Multipath only matters on nodes that attach external SAN storage: control
    // (cinder-volume, glance/manila) and compute (nova volume attach) -- also where
    // the FC/iSCSI HBAs live. Pure storage (local ceph OSDs) and edge nodes have no
    // SAN attachment, so multipathd stays disabled there.
    bool enabled = IsControl(s_eCubeRole) || IsCompute(s_eCubeRole);

    SystemdCommitService(enabled, NAME);
    if (!enabled)
        return true;

    // Reload /etc/multipath.conf so the overrides{} take effect, then refresh maps.
    HexUtilSystemF(0, 0, "/usr/sbin/multipathd reconfigure");

    if (HexUtilSystemF(0, 0, "/usr/sbin/hex_sdk storage_update_device_maps") != 0) {
        HexLogError("failed to update multipath device maps");
        return false;
    }

    return true;
}

CONFIG_MODULE(multipath, Init, 0, 0, 0, Commit);

// observe node role + cinder external-storage backends so the gate + CommitCheck
// react to a role change or an operator adding/removing a SAN backend
CONFIG_OBSERVES(multipath, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(multipath, cinder, ParseCinder, NotifyCinder);

// preserve operator-tuned per-backend multipath config across upgrades
CONFIG_MIGRATE(multipath, "/etc/multipath/conf.d");

CONFIG_SUPPORT_COMMAND("/usr/sbin/multipath -ll");
