// CUBE SDK

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
#include <cluster.hpp>

#include "include/role_cubesys.h"

static const char NAME[] = "influxdb";
static const char CURATOR[] = "/etc/cron.d/influx-curator";

#define DEF_EXT ".def"
#define CONF    "/etc/influxdb/influxdb.conf"
#define TSDB_RP "def"        // default rp, low-cardinality metrics
#define HC_TSDB_RP "hc"      // high cardinality rp -- sflow and vrouter.top

static CubeRole_e s_eCubeRole;

static bool s_bCubeModified = false;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("influxdb", "/var/log/influxdb/*.log", DAILY, 128, 0, true);

// external global variables

// public tunings
CONFIG_TUNING_INT(INFLUXDB_CURATOR_RP, "influxdb.curator.rp", TUNING_PUB, "influxdb curator retention policy in days.", 7, 0, 365);
// Retention is two policies per database, split by cardinality: 'def' carries the
// low-cardinality series whose count scales with node count (host cpu/mem/disk,
// ceph_*), 'hc' carries sflow and vrouter.top, whose series count scales with
// traffic -- one per flow tuple -- and would otherwise dominate the TSDB index.
//
// Duration and shard duration are tuned together on purpose. InfluxDB never deletes
// individual points; it drops whole shard groups, and only once the entire group is
// older than the duration. So a point written at the start of a shard group survives
// duration + shard duration, and disk is freed in shard-sized steps. A long duration
// with a coarse shard therefore both overshoots and frees space in cliffs -- the
// previous 364d/35d pair kept data for up to 399 days and reclaimed it five weeks at
// a time, on the same partition as the OS.
CONFIG_TUNING_INT(INFLUXDB_RP_DAYS, "influxdb.def.rp.duration", TUNING_PUB, "influxdb default retention policy duration in days.", 14, 1, 3650);
CONFIG_TUNING_INT(INFLUXDB_SGP_DAYS, "influxdb.def.rp.shard", TUNING_PUB, "influxdb default retention policy shard group duration in days.", 7, 1, 365);
CONFIG_TUNING_INT(INFLUXDB_HC_RP_DAYS, "influxdb.hc.rp.duration", TUNING_PUB, "influxdb high-cardinality retention policy duration in days.", 7, 1, 3650);
CONFIG_TUNING_INT(INFLUXDB_HC_SGP_DAYS, "influxdb.hc.rp.shard", TUNING_PUB, "influxdb high-cardinality retention policy shard group duration in days.", 2, 1, 365);

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);

// parse tunings
PARSE_TUNING_INT(s_curatorRp, INFLUXDB_CURATOR_RP);
PARSE_TUNING_INT(s_rpDays, INFLUXDB_RP_DAYS);
PARSE_TUNING_INT(s_sgpDays, INFLUXDB_SGP_DAYS);
PARSE_TUNING_INT(s_hcRpDays, INFLUXDB_HC_RP_DAYS);
PARSE_TUNING_INT(s_hcSgpDays, INFLUXDB_HC_SGP_DAYS);
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

static bool
CreateDBs(int rpDays, int sgpDays, int hcRpDays, int hcSgpDays)
{
    // Re-creation is allowed
    HexUtilSystemF(0, 0, HEX_SDK " wait_for_service :: 8086 90");

    // A shard group wider than the policy it lives in is rejected by InfluxDB, and
    // would mean the policy could never drop anything. Clamp rather than fail the
    // commit, and say so.
    if (sgpDays > rpDays) {
        HexLogWarning("influxdb: def shard duration %dd exceeds retention %dd, clamping to %dd",
                      sgpDays, rpDays, rpDays);
        sgpDays = rpDays;
    }
    if (hcSgpDays > hcRpDays) {
        HexLogWarning("influxdb: hc shard duration %dd exceeds retention %dd, clamping to %dd",
                      hcSgpDays, hcRpDays, hcRpDays);
        hcSgpDays = hcRpDays;
    }

    HexLogInfo("updating influxdb policies: def %dd/shard %dd, hc %dd/shard %dd",
               rpDays, sgpDays, hcRpDays, hcSgpDays);

    std::string dbs[] = {"telegraf", "monasca", "events"};

    for (const std::string &db : dbs) {
        HexSystemF(0, "influx -execute 'CREATE DATABASE %s WITH DURATION %dd SHARD DURATION %dd NAME %s'",
                      db.c_str(), rpDays, sgpDays, TSDB_RP);

        HexSystemF(0, "influx -execute 'CREATE RETENTION POLICY %s ON %s DURATION %dd "
                      "REPLICATION 1 SHARD DURATION %dd'",
                      TSDB_RP, db.c_str(), rpDays, sgpDays);
        HexSystemF(0, "influx -execute 'ALTER RETENTION POLICY %s ON %s DURATION %dd DEFAULT'",
                      TSDB_RP, db.c_str(), rpDays);
        HexSystemF(0, "influx -execute 'ALTER RETENTION POLICY %s ON %s DEFAULT'",
                      TSDB_RP, db.c_str());
        HexSystemF(0, "influx -execute 'ALTER RETENTION POLICY %s ON %s SHARD DURATION %dd DEFAULT'",
                      TSDB_RP, db.c_str(), sgpDays);

        HexSystemF(0, "influx -execute 'CREATE RETENTION POLICY %s ON %s DURATION %dd "
                      "REPLICATION 1 SHARD DURATION %dd'",
                      HC_TSDB_RP, db.c_str(), hcRpDays, hcSgpDays);
        HexSystemF(0, "influx -execute 'ALTER RETENTION POLICY %s ON %s DURATION %dd'",
                      HC_TSDB_RP, db.c_str(), hcRpDays);
        HexSystemF(0, "influx -execute 'ALTER RETENTION POLICY %s ON %s SHARD DURATION %dd'",
                      HC_TSDB_RP, db.c_str(), hcSgpDays);
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

    return modified | s_bCubeModified;
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = IsControl(s_eCubeRole) && !IsModerator(s_eCubeRole);

    SystemdCommitService(enabled, NAME);

    if (enabled) {
        WriteLogRotateConf(log_conf);
        CreateDBs(s_rpDays.newValue(), s_sgpDays.newValue(),
                  s_hcRpDays.newValue(), s_hcSgpDays.newValue());
    }

    CuratorCronJob(s_curatorRp.newValue());

    return true;
}

CONFIG_MODULE(influxdb, 0, Parse, 0, 0, Commit);
CONFIG_REQUIRES(influxdb, ceph_dashboard_idp);

// extra tunings
CONFIG_OBSERVES(influxdb, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(influxdb, "/var/lib/influxdb");

// influx 7d export is considered too large to place in support file (~5GB)
//CONFIG_SUPPORT_COMMAND(HEX_SDK " support_influxdb $HEX_SUPPORT_DIR");

