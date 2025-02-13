#include <unistd.h>
#include <hex/log.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/process_util.h>
#include <hex/dryrun.h>
#include <hex/tuning.h>
#include <hex/logrotate.h>

#include <cube/network.h>
#include <cube/cluster.h>

typedef std::map<std::string, ConfigUInt> MtuMap;

static const char CONFIGURED_FILE[] = "/etc/appliance/state/configured";
static bool s_bMtuModified = false;
static MtuMap s_Mtu;
static bool s_bNovaModified = false;

static LogRotateConf log_conf("k3s", "/var/log/k3s.log", DAILY, 128, 0, true);

// using external tunings
CONFIG_GLOBAL_STR_REF(MGMT_IF);
CONFIG_TUNING_SPEC_UINT(NET_IF_MTU);
CONFIG_TUNING_SPEC_UINT(NOVA_RESV_HOST_VCPU);
CONFIG_TUNING_SPEC_UINT(NOVA_RESV_HOST_MEM);

// parse tunings
PARSE_TUNING_X_UINT(s_resvHostVcpu, NOVA_RESV_HOST_VCPU, 0);
PARSE_TUNING_X_UINT(s_resvHostMem, NOVA_RESV_HOST_MEM, 0);

static bool
ParseNova(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 0);
    return true;
}

static void
NotifyNova(bool modified)
{
    s_bNovaModified = s_resvHostVcpu.modified() | s_resvHostMem.modified();
}

static bool
ParseNet(const char *name, const char *value, bool isNew)
{
    const char* p = 0;

    if (HexMatchPrefix(name, NET_IF_MTU.format.c_str(), &p)) {
        ConfigUInt& m = s_Mtu[p];
        m.parse(value, isNew);
    }

    return true;
}

static void
CheckMTU()
{
    std::string mgmtIf = G(MGMT_IF);
    for (auto& m : s_Mtu) {
        std::string ifname = m.first;
        std::string pIf = GetParentIf(ifname);
        ConfigUInt& mtu = m.second;

        if (pIf == mgmtIf && mtu.modified()) {
            s_bMtuModified = true;
        }
    }
    HexLogInfo("k3s MTU modified %d", s_bMtuModified);
}

static bool
Commit(bool modified, int dryLevel)
{
    // TODO: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    CheckMTU();

    // Reconfigure MTU when applying MTU tunning
    if (s_bMtuModified && !IsBootstrap() && access(CONFIGURED_FILE, F_OK) == 0) {
        HexUtilSystemF(0, 0, "/usr/sbin/hex_sdk k3s_reconfigure_mtu");
        HexLogInfo("k3s MTU reconfigured");
    } else {
        HexUtilSystemF(0, 0, "cubectl config commit k3s --stacktrace");
    }

    WriteLogRotateConf(log_conf);

    return true;
}

static bool
CommitLast(bool modified, int dryLevel)
{
    HEX_DRYRUN_BARRIER(dryLevel, true);
    if (!s_bNovaModified) {
        return true;
    }

    HexUtilSystemF(0, 0, "cubectl config commit k3s_last --stacktrace");
    return true;
}

static int
ClusterStartMain(int argc, char **argv)
{
    if (argc != 1) {
        return EXIT_FAILURE;
    }

    HexUtilSystemF(0, 0, "cubectl config commit k3s_last --stacktrace");
    return EXIT_SUCCESS;
}

CONFIG_MODULE(k3s, 0, 0, 0, 0, Commit);
CONFIG_MODULE(k3s_last, 0, 0, 0, 0, CommitLast);
CONFIG_REQUIRES(k3s, cluster);
CONFIG_REQUIRES(k3s, docker);

// bind9 will update /etc/resolv.conf
CONFIG_REQUIRES(k3s, dns);
CONFIG_REQUIRES(k3s_last, nova);

// Observe MTU changes
CONFIG_OBSERVES(k3s, net, ParseNet, 0);
CONFIG_OBSERVES(k3s_last, nova, ParseNova, NotifyNova);

// Inculde embedded etcd and all workloads and pv on k3s
CONFIG_MIGRATE(k3s, "/var/lib/rancher/k3s");

CONFIG_TRIGGER_WITH_SETTINGS(k3s_last, "cluster_start", ClusterStartMain);
