// CUBE

#include <unistd.h>

#include <hex/log.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/string_util.h>
#include <hex/filesystem.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <hex/logrotate.h>

#include <cube/cluster.h>
#include <cube/systemd_util.h>

#include "include/role_cubesys.h"

const static char USER[] = "opensearch";
const static char GROUP[] = "opensearch";

const static char NAME[] = "opensearch";
const static char CONF[] = "/etc/opensearch/opensearch.yml";
const static char JVM_OPTS[] = "/etc/opensearch/jvm.options.d/cube.options";
const static char RUNDIR[] = "/run/opensearch";
const static char CLUSTER_ID[] = "MRMGsDtEMaVqWRFl";

const static char CURATOR[] = "/etc/cron.d/ec-curator";

static ConfigString s_hostname;

static bool s_bCubeModified = false;
static bool s_bNetModified = false;

static CubeRole_e s_eCubeRole;

// external global variables
CONFIG_GLOBAL_BOOL_REF(IS_MASTER);
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);

// private tunings
CONFIG_TUNING_INT(OPENSEARCH_CURATOR_RP, "opensearch.curator.rp", TUNING_PUB, "opensearch curator retention policy in days.", 7, 0, 365);
CONFIG_TUNING_BOOL(OPENSEARCH_ENABLED, "opensearch.enabled", TUNING_UNPUB, "Set to true to enable opensearch.", true);
CONFIG_TUNING_STR(OPENSEARCH_CLUSTER_ID, "opensearch.cluster.id", TUNING_UNPUB, "opensearch cluster id.", CLUSTER_ID, ValidateNone);

// public tunings
CONFIG_TUNING_INT(OPENSEARCH_HEAP_SIZE, "opensearch.heap.size", TUNING_PUB, "opensearch heap size in GB.", 2, 1, 1024);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, OPENSEARCH_ENABLED);
PARSE_TUNING_INT(s_curatorRp, OPENSEARCH_CURATOR_RP);
PARSE_TUNING_STR(s_clusterId, OPENSEARCH_CLUSTER_ID);
PARSE_TUNING_INT(s_heapSize, OPENSEARCH_HEAP_SIZE);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);

static bool
SetShardPerNode(const bool ha, const int rp)
{
    int idxPerDay = 1000;
    int shardPerDay = idxPerDay * (ha ? 2 : 1); // 1 shards and 1 replica per index: 1 x (1 + 1) = 2
    int shardPerNode = shardPerDay * rp;

    HexUtilSystemF(0, 0, HEX_SDK " opensearch_shard_per_node_set %d", shardPerNode);

    return true;
}

static bool
CuratorCronJob(int rp)
{
    if(IsControl(s_eCubeRole)) {
        FILE *fout = fopen(CURATOR, "w");
        if (!fout) {
            HexLogError("Unable to write ec curator job: %s", CURATOR);
            return false;
        }

        // at 2 AM every day
        fprintf(fout, "0 2 * * * root " HEX_SDK " opensearch_index_curator %d\n", rp);
        fclose(fout);

        if(HexSetFileMode(CURATOR, "root", "root", 0644) != 0) {
            HexLogError("Unable to set file %s mode/permission", CURATOR);
            return false;
        }
    }
    else {
        unlink(CURATOR);
    }

    return true;
}

static bool
WriteConfig(const bool ha, const std::string& clusterid, const std::string& ctrl,
            const std::string& ctrlIp, const std::string& ctrlAddrs, int heap)
{
    if (!IsControl(s_eCubeRole))
        return true;

    FILE *fout = fopen(CONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s config: %s", NAME, CONF);
        return false;
    }

    fprintf(fout, "cluster.name: cube-%s\n", clusterid.c_str());
    fprintf(fout, "node.name: \"%s\"\n", ctrl.c_str());
    fprintf(fout, "network.host: [_local_, %s]\n", ctrlIp.c_str());
    fprintf(fout, "http.port: 9200\n");
    fprintf(fout, "transport.tcp.port: 9300-9400\n");
    fprintf(fout, "path.logs: /var/log/opensearch\n");
    fprintf(fout, "path.data: /var/lib/opensearch\n");
    fprintf(fout, "# node.max_local_storage_nodes: 3\n");
    fprintf(fout, "plugins.security.disabled: true\n");

    if (!ha) {
        fprintf(fout, "cluster.initial_master_nodes: %s\n", ctrlIp.c_str());
    }
    else {
        fprintf(fout, "node.master: true\n");
        fprintf(fout, "node.data: true\n");

        // turn ip1,ip2,ip3 to "ip1","ip2","ip3"
        auto group = hex_string_util::split(ctrlAddrs, ',');
        if (G(IS_MASTER) && access(CONTROL_REJOIN, F_OK) == 0)
            fprintf(fout, "cluster.initial_master_nodes: %s\n", group[1].c_str());
        else
            fprintf(fout, "cluster.initial_master_nodes: %s\n", group[0].c_str());
        std::string servers = "";
        for (size_t i = 0 ; i < group.size() ; i++) {
            servers += "\"" + group[i] + "\"";
            if (i + 1 < group.size())
                servers += ",";
        }

        fprintf(fout, "discovery.zen.ping.unicast.hosts: [%s]\n", servers.c_str());
    }

    fclose(fout);
/*
    FILE *fheap = fopen(JVM_OPTS, "w");
    if (!fout) {
        HexLogError("Unable to write %s jvm options: %s", NAME, JVM_OPTS);
        return false;
    }

    fprintf(fheap, "-Xms%dg\n", heap);
    fprintf(fheap, "-Xmx%dg\n", heap);
    fprintf(fheap, "# CVE-2021-44228\n");
    fprintf(fheap, "-Dlog4j2.formatMsgNoLookups=true\n");

    fclose(fheap);
*/
    return true;
}

static bool
ParseNet(const char *name, const char *value, bool isNew)
{
    if (strcmp(name, NET_HOSTNAME) == 0) {
        s_hostname.parse(value, isNew);
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

static void
NotifyNet(bool modified)
{
    s_bNetModified = s_hostname.modified();
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
Init()
{
    if (HexMakeDir(RUNDIR, USER, GROUP, 0755) != 0)
        return false;

    return true;
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        return true;
    }

    return modified | s_bCubeModified | G_MOD(MGMT_ADDR);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || IsEdge(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    std::string myip = G(MGMT_ADDR);
    std::string cId = GetSaltKey(s_saltkey, s_clusterId.newValue(), s_seed.newValue());
    bool enabled = IsControl(s_eCubeRole) && s_enabled;

    WriteConfig(s_ha, cId, s_hostname.newValue(), myip, s_ctrlAddrs.newValue(), s_heapSize);
    SystemdCommitService(enabled, NAME, true);

    // wait for service ready
    if (enabled) {
        HexUtilSystemF(0, 0, HEX_SDK " wait_for_service %s 9200 90", myip.c_str());
        SetShardPerNode(s_ha, s_curatorRp);
        HexUtilSystemF(0, 0, HEX_SDK " opensearch_shard_delete_unassigned");
    }

    CuratorCronJob(s_curatorRp.newValue());

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_es\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    bool enabled = IsControl(s_eCubeRole) && s_enabled;
    SystemdCommitService(enabled, NAME, true);

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_es, RestartMain, RestartUsage);

CONFIG_MODULE(opensearch, Init, Parse, 0, 0, Commit);
CONFIG_REQUIRES(opensearch, cube_scan);

// extra tunings
CONFIG_OBSERVES(opensearch, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(opensearch, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(opensearch, "/var/lib/opensearch");

CONFIG_SUPPORT_COMMAND(HEX_SDK " opensearch_stats");
CONFIG_SUPPORT_COMMAND(HEX_SDK " opensearch_index_list");

