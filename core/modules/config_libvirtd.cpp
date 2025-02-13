// CUBE

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/dryrun.h>

#include <cube/systemd_util.h>
#include "include/role_cubesys.h"

const static char RUNDIR[] = "/run/libvirt";
const static char NAME[] = "virtqemud";
const static char VND_NAME[] = "virtnodedevd";
const static char VLD_NAME[] = "virtlogd";
const static char VSD_NAME[] = "virtsecretd";
static const char KSM[] = "ksm";
static const char KSMTUNED[] = "ksmtuned";

static bool s_bEnableChanged = false;

static bool s_bCubeModified = false;
static CubeRole_e s_eCubeRole;

// private tunings
CONFIG_TUNING_BOOL(LIBVIRTD_ENABLED, "libvirtd.enabled", TUNING_UNPUB, "Set to true to enable libvirtd.", true);

// external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, LIBVIRTD_ENABLED);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);

static bool
ParseCube(const char *name, const char *value, bool isNew)
{
    // OBSERVER tunings should has been validated in its module
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
Init()
{
    if (HexMakeDir(RUNDIR, NULL, NULL, 0755) != 0)
        return false;

    // https://forum.proxmox.com/threads/how-to-stop-warnings-kvm-vcpu0-ignored-rdmsr.28552/
    HexSystemF(0, "echo 0 > /sys/module/kvm/parameters/report_ignored_msrs");

    return true;
}

static bool
Parse(const char *name, const char *value, bool isNew)
{
    bool r = true;

    TuneStatus s = ParseTune(name, value, isNew);
    if (s == TUNE_INVALID_NAME) {
        HexLogWarning("Unknown settings name \"%s\" = \"%s\" ignored", name, value);
    }
    else if (s == TUNE_INVALID_VALUE) {
        HexLogError("Invalid settings value \"%s\" = \"%s\"", name, value);
        r = false;
    }
    return r;
}

static bool
Prepare(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        s_bEnableChanged = true;
        return true;
    }

    s_bEnableChanged = modified | s_bCubeModified;

    return true;
}

static bool
Commit(bool modified, int dryLevel)
{
    // TODO: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (s_bEnableChanged) {
        bool enabled = s_enabled && IsCompute(s_eCubeRole);
        SystemdCommitService(enabled, NAME, true);
        SystemdCommitService(enabled, VND_NAME, true);
        SystemdCommitService(enabled, VLD_NAME, true);
        SystemdCommitService(enabled, VSD_NAME, true);
        SystemdCommitService(enabled, KSM, true);
        SystemdCommitService(enabled, KSMTUNED, true);
    }

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_libvirtd\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    if (IsCompute(s_eCubeRole)) {
        SystemdCommitService(s_enabled, NAME, true);
        SystemdCommitService(s_enabled, VND_NAME, true);
        SystemdCommitService(s_enabled, VLD_NAME, true);
        SystemdCommitService(s_enabled, VSD_NAME, true);
        SystemdCommitService(s_enabled, KSM, true);
        SystemdCommitService(s_enabled, KSMTUNED, true);
    }

    return EXIT_SUCCESS;
}

static int
ClusterStartMain(int argc, char **argv)
{
    if (argc != 1) {
        return EXIT_FAILURE;
    }

    // post actions for db migration
    HexUtilSystemF(0, 0, HEX_SDK " migrate_libvirt");

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_libvirtd, RestartMain, RestartUsage);

CONFIG_MODULE(libvirtd, Init, Parse, 0, Prepare, Commit);
CONFIG_REQUIRES(libvirtd, cube_scan);

// extra tunings
CONFIG_OBSERVES(libvirtd, cubesys, ParseCube, NotifyCube);

CONFIG_TRIGGER_WITH_SETTINGS(libvirtd, "cluster_start", ClusterStartMain);
