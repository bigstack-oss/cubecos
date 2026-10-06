// CUBE SDK

#include <hex/log.h>
#include <hex/config_module.h>
#include <hex/process_util.h>
#include <hex/dryrun.h>

#include <cluster.hpp>

static bool
Commit(bool modified, int dryLevel)
{
    // TODO: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    HexUtilSystemF(0, 0, "cubectl config commit docker --stacktrace");

    return true;
}

CONFIG_MODULE(docker, 0, 0, 0, 0, Commit);
CONFIG_REQUIRES(docker, cluster);

// cubectl keeps an existing daemon.json, adding only its registry, so a site's
// own settings (e.g. a bip and default-address-pools moving docker off
// 172.17.0.0/16) last until an upgrade boots a partition with none: carry it.
CONFIG_MIGRATE(docker, "/etc/docker/daemon.json");
//CONFIG_MIGRATE(docker, "/var/lib/docker");
