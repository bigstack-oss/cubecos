#include <hex/log.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/process_util.h>
#include <hex/dryrun.h>

#include <cube/cluster.h>

// public tunings
CONFIG_TUNING_BOOL(RANCHER_ENABLED, "rancher.enabled", TUNING_UNPUB, "Set to true to enable Kubernetes as a Service.", true);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, RANCHER_ENABLED);

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
Commit(bool modified, int dryLevel)
{
    // TODO: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    bool enabled = s_enabled;

    if (enabled)
        HexUtilSystemF(0, 0, "cubectl config commit rancher --stacktrace");
    else
        HexUtilSystemF(0, 0, "cubectl config reset rancher --stacktrace");

    return true;
}

CONFIG_MODULE(rancher, 0, Parse, 0, 0, Commit);
CONFIG_REQUIRES(rancher, cluster);
CONFIG_REQUIRES(rancher, docker);
CONFIG_REQUIRES(rancher, k3s);
CONFIG_REQUIRES(rancher, keycloak);

CONFIG_MIGRATE(rancher, "/root/.rancher");

// For rancher provisioned k8s on compute nodes
CONFIG_MIGRATE(rancher, "/var/lib/rancher/rke");
CONFIG_MIGRATE(rancher, "/var/lib/etcd");
CONFIG_MIGRATE(rancher, "/var/lib/cni");
CONFIG_MIGRATE(rancher, "/etc/kubernetes");
CONFIG_MIGRATE(rancher, "/etc/cni");
CONFIG_MIGRATE(rancher, "/opt/rke");
