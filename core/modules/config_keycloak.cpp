#include <hex/log.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/process_util.h>
#include <hex/dryrun.h>

#include <cube/cluster.h>

static bool
Commit(bool modified, int dryLevel)
{
    // TODO: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    HexUtilSystemF(0, 0, "cubectl config commit keycloak --stacktrace");

    return true;
}

CONFIG_MODULE(keycloak, 0, 0, 0, 0, Commit);
CONFIG_REQUIRES(keycloak, k3s);
CONFIG_REQUIRES(keycloak, mysql);

CONFIG_MIGRATE(keycloak, "/etc/keycloak");
