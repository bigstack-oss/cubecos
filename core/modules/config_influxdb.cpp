// CUBE

#include <unistd.h>

#include <hex/log.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/filesystem.h>
#include <hex/logrotate.h>

#include <cube/systemd_util.h>
#include <cube/cluster.h>

#include "include/role_cubesys.h"

static const char NAME[] = "influxdb";
static const char CURATOR[] = "/etc/cron.d/influx-curator";

#define DEF_EXT ".def"
#define CONF    "/etc/influxdb/influxdb.conf"
#define MAKRER  "/etc/appliance/state/ceph_mgr_influx_enabled"
#define INFLUX_INTERVAL 60
#define TSDB_RP "def"     // default rp
#define RP_DURATION "52w" // 1 years
#define SGP_DURATION "5w" // 1 month
#define HC_TSDB_RP "hc"      // high cardinality rp
#define HC_RP_DURATION "2w"  // 2 weeks
#define HC_SGP_DURATION "1w" // 1 week

static CubeRole_e s_eCubeRole;

static bool s_bCubeModified = false;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("influxdb", "/var/log/influxdb/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// public tunings
CONFIG_TUNING_INT(INFLUXDB_CURATOR_RP, "influxdb.curator.rp", TUNING_PUB, "influxdb curator retention policy in days.", 7, 0, 365);

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);

// parse tunings
PARSE_TUNING_INT(s_curatorRp, INFLUXDB_CURATOR_RP);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);

static bool
CuratorCronJob(int rp)
{
    if(IsControl(s_eCubeRole)) {
        FILE *fout = fopen(CURATOR, "w");
        if (!fout) {
            HexLogError("Unable to write inflxdb curator job: %s", CURATOR);
            return false;
        }

        // at 3 AM every day
        fprintf(fout, "0 3 * * * root " HEX_SDK " stats_inactive_vm_drop %dd\n", rp);
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

// Enable Ceph influx plugin so that ceph-mgr can report state to influxdb
/* Default config settings
        'hostname': None,
        'port': 8086,
        'database': 'ceph',
        'username': None,
        'password': None,
        'interval': 5,
        'ssl': 'false',
        'verify_ssl': 'true'
*/
static bool
EnableCephInfluxPlugin(bool update, const std::string sharedId)
{
    struct stat ms;

    if (!update && stat(MAKRER, &ms) == 0)
        return true;

    HexLogInfo("updating influxdb ceph plugin");

    if (stat(MAKRER, &ms) != 0) {
        HexSystemF(0, "timeout 10 ceph mgr module enable influx 2>/dev/null");
        HexSystemF(0, "touch " MAKRER);
    }

    // specifiy a timeout for ceph cmd since it may hang due to bad connectivity
    // or master node runs restart when other nodes are down (cluster start)
    // NOTE: timeout of HexSystemF doesn't work in this case
    //       since parent doesn't kill child process when timeout occurs
    HexSystemF(0, "timeout 10 ceph influx config-set interval %d >/dev/null", INFLUX_INTERVAL);
    HexSystemF(0, "timeout 10 ceph influx config-set hostname %s >/dev/null", sharedId.c_str());
    HexSystemF(0, "timeout 10 ceph influx config-set port 8086 >/dev/null");

    return true;
}

static bool
CreateDBs()
{
    // Re-creation is allowed
    HexUtilSystemF(0, 0, HEX_SDK " wait_for_service 127.0.0.1 8086 90");
    HexLogInfo("updating influxdb polices");

    std::string dbs[] = {"telegraf", "ceph", "monasca", "events"};

    for (const std::string &db : dbs) {
        HexSystemF(0, "influx -execute 'CREATE DATABASE %s WITH DURATION %s SHARD DURATION %s NAME %s'",
                      db.c_str(), RP_DURATION, SGP_DURATION, TSDB_RP);

        HexSystemF(0, "influx -execute 'CREATE RETENTION POLICY %s ON %s DURATION %s "
                      "REPLICATION 1 SHARD DURATION %s'",
                      TSDB_RP, db.c_str(), RP_DURATION, SGP_DURATION);
        HexSystemF(0, "influx -execute 'ALTER RETENTION POLICY %s ON %s DURATION %s DEFAULT'",
                      TSDB_RP, db.c_str(), RP_DURATION);
        HexSystemF(0, "influx -execute 'ALTER RETENTION POLICY %s ON %s DEFAULT'",
                      TSDB_RP, db.c_str());
        HexSystemF(0, "influx -execute 'ALTER RETENTION POLICY %s ON %s SHARD DURATION %s DEFAULT'",
                      TSDB_RP, db.c_str(), SGP_DURATION);

        HexSystemF(0, "influx -execute 'CREATE RETENTION POLICY %s ON %s DURATION %s "
                      "REPLICATION 1 SHARD DURATION %s'",
                      HC_TSDB_RP, db.c_str(), HC_RP_DURATION, HC_SGP_DURATION);
        HexSystemF(0, "influx -execute 'ALTER RETENTION POLICY %s ON %s DURATION %s'",
                      HC_TSDB_RP, db.c_str(), HC_RP_DURATION);
        HexSystemF(0, "influx -execute 'ALTER RETENTION POLICY %s ON %s SHARD DURATION %s'",
                      HC_TSDB_RP, db.c_str(), HC_SGP_DURATION);
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
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        return true;
    }

    return modified | s_bCubeModified | G_MOD(SHARED_ID);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = IsControl(s_eCubeRole) && !IsModerator(s_eCubeRole);
    std::string sharedId = G(SHARED_ID);

    SystemdCommitService(enabled, NAME);

    if (enabled) {
        EnableCephInfluxPlugin(true, sharedId);
        WriteLogRotateConf(log_conf);
        CreateDBs();
    }

    CuratorCronJob(s_curatorRp.newValue());

    return true;
}

static int
ClusterReadyMain(int argc, char **argv)
{
    bool enabled = IsControl(s_eCubeRole);
    std::string sharedId = G(SHARED_ID);

    if (enabled)
        EnableCephInfluxPlugin(true, sharedId);

    return EXIT_SUCCESS;
}

CONFIG_MODULE(influxdb, 0, Parse, 0, 0, Commit);
CONFIG_REQUIRES(influxdb, ceph_dashboard_idp);

// extra tunings
CONFIG_OBSERVES(influxdb, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(influxdb, "/var/lib/influxdb");
CONFIG_MIGRATE(influxdb, MAKRER);

// influx 7d export is considered too large to place in support file (~5GB)
//CONFIG_SUPPORT_COMMAND(HEX_SDK " support_influxdb $HEX_SUPPORT_DIR");

CONFIG_TRIGGER_WITH_SETTINGS(influxdb, "cluster_ready", ClusterReadyMain);

