// CUBE

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <hex/logrotate.h>

#include <cube/cluster.h>
#include <cube/systemd_util.h>

#include "include/role_cubesys.h"
#include "mysql_util.h"

const static char CURATOR[] = "/etc/cron.d/mysql-backup-curator";

const static char MYD_CNF[] = "/etc/my.cnf.d/cube.cnf";
const static char ERROR_LOG[] = "/var/log/mariadb/mysql_error.log";

const static char DATADIR[] = "/var/lib/mysql";
const static char BACKDIR[] = "/var/lib/_mysql";
const static char SETUP_MARK[] = "/etc/appliance/state/mysql_done";
const static char FORCE_NEW_MARK[] = "/etc/appliance/state/mysql_new_cluster";

const static char USER[] = "mysql";
const static char GROUP[] = "mysql";
const static char NAME[] = "mariadb";

static ConfigString s_hostname;

static bool s_bSetup = true;
static bool s_bForceNew = false;

static bool s_bCubeModified = false;
static bool s_bNetModified = false;

static CubeRole_e s_eCubeRole;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("mysql", "/var/log/mysql/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_BOOL_REF(IS_MASTER);
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);

// private tunings
CONFIG_TUNING_INT(MYSQL_CURATOR_RP, "mysql.backup.curator.rp", TUNING_PUB, "mysql backup retention policy in weeks.", 14, 0, 52);
CONFIG_TUNING_BOOL(MYSQL_ENABLED, "mysql.enabled", TUNING_UNPUB, "Set to true to enable iaas db.", true);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, MYSQL_ENABLED);
PARSE_TUNING_INT(s_curatorRp, MYSQL_CURATOR_RP);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);

static bool
CuratorCronJob(int rp)
{
    if(IsControl(s_eCubeRole)) {
        FILE *fout = fopen(CURATOR, "w");
        if (!fout) {
            HexLogError("Unable to write ec curator job: %s", CURATOR);
            return false;
        }

        // at 4 AM every sunday
        fprintf(fout, "0 4 * * SUN root " HEX_SDK " support_mysql_backup_job %d\n", rp);
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
SetupCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    struct stat ms;

    if(stat(SETUP_MARK, &ms) != 0) {
        s_bSetup = false;
    }

    if(stat(FORCE_NEW_MARK, &ms) == 0) {
        s_bForceNew = true;
    }

    return true;
}

static bool
UpdateCheck()
{
    if (!IsControl(s_eCubeRole))
        return true;

    if (access(BACKDIR, F_OK) == 0) {
        std::vector<const char*> command;
        command.push_back("/usr/bin/mysql_upgrade");
        command.push_back("-u");
        command.push_back("root");
        command.push_back("--skip-write-binlog");
        command.push_back(0);

        if (HexSpawnVQ(0, NO_STDOUT | NO_STDERR, (char* const*)&command[0]) == 0) {
            HexSpawn(0, "/bin/rm", "-rf", BACKDIR, NULL);
            HexLogInfo("upgrade database successfully");
            return true;
        }
        else {
            HexLogError("failed to upgrade database");
            return false;
        }
    }

    return true;
}

static bool
WriteConfig(const bool ha, const std::string& ctrl, const std::string& ctrlIp, const std::string& ctrlAddrs)
{
    if (!IsControl(s_eCubeRole))
        return true;

    FILE *fout = fopen(MYD_CNF, "w");
    if (!fout) {
        HexLogError("Unable to write %s config: %s", NAME, MYD_CNF);
        return false;
    }

    fprintf(fout, "[mysqld]\n");
    fprintf(fout, "bind-address = %s\n", ctrlIp.c_str());
    fprintf(fout, "log_error=%s\n", ERROR_LOG);
    fprintf(fout, "default-storage-engine = innodb\n");
    fprintf(fout, "max_connections = 10000\n");
    fprintf(fout, "max_connect_errors = 10000\n");
    fprintf(fout, "max_allowed_packet = 256M\n");
    fprintf(fout, "collation-server = utf8_general_ci\n");
    fprintf(fout, "character-set-server = utf8\n");
    fprintf(fout, "binlog_format = ROW\n");
    fprintf(fout, "log_warnings = 1\n");
    fprintf(fout, "skip-host-cache\n");
    fprintf(fout, "skip-name-resolve\n");

    fprintf(fout, "[mysqld_safe]\n");
    fprintf(fout, "log_error=%s\n", ERROR_LOG);

    if (ha) {
        fprintf(fout, "query_cache_size = 0\n");
        fprintf(fout, "query_cache_type = 0\n");
    }

    // InnoDB configuration
    fprintf(fout, "innodb_file_per_table = on\n");
    fprintf(fout, "innodb_autoinc_lock_mode = 2\n");
    fprintf(fout, "innodb_flush_log_at_trx_commit = 0\n");

    // Galera Provider Configuration
    if (ha) {
        fprintf(fout, "innodb_buffer_pool_size = 122M\n");
        fprintf(fout, "[galera]\n");
        fprintf(fout, "wsrep_on = ON\n");
        fprintf(fout, "wsrep_slave_threads = 32\n");
        fprintf(fout, "wsrep_slave_FK_checks = OFF\n");
        fprintf(fout, "wsrep_provider = /usr/lib64/galera/libgalera_smm.so\n");
        fprintf(fout, "wsrep_provider_options = \"pc.recovery=TRUE;gcache.size=300M;pc.ignore_sb=TRUE\"\n");
        fprintf(fout, "wsrep_cluster_name = \"cube_galera_cluster\"\n");
        fprintf(fout, "wsrep_cluster_address = \"gcomm://%s\"\n", ctrlAddrs.c_str());
        fprintf(fout, "wsrep_sst_method = rsync\n");
        fprintf(fout, "wsrep_node_name = %s\n", ctrl.c_str());
        fprintf(fout, "wsrep_node_address = %s\n", ctrlIp.c_str());
        fprintf(fout, "wsrep_retry_autocommit = 32\n");
        fprintf(fout, "wsrep_log_conflicts = ON\n");
    }

    fclose(fout);

    return true;
}

static bool
SetupCluster(bool enabled, bool isMaster, bool force, const std::string& ctrlAddrs)
{
    if (!enabled)
        return true;

    if (force) {
        HexLogInfo("force mysql bootstrap");
        if (isMaster) {
            HexLogInfo("stop all mysql processes of the cluster");
            HexUtilSystemF(0, 0, "cubectl node exec --parallel --hosts %s systemctl stop %s", ctrlAddrs.c_str(), NAME);
            HexSystemF(0, "sed -i 's/^\\(safe_to_bootstrap\\s*:\\s*\\).*$/\\11/' /var/lib/mysql/grastate.dat");
        }
        else
            HexSystemF(0, "rm -f /var/lib/mysql/grastate.dat /var/lib/mysql/ib_log*");
        unlink(FORCE_NEW_MARK);
    }

    if (isMaster) {
        HexUtilSystemF(0, 0, "galera_new_cluster");
    }

    HexSystemF(0, "touch %s", SETUP_MARK);
    s_bSetup = true;

    if (!isMaster) {
        SystemdCommitService(enabled, NAME, true);
    }

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
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        return true;
    }

    return modified | s_bNetModified | s_bCubeModified |
                    G_MOD(IS_MASTER) | G_MOD(MGMT_ADDR);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = IsControl(s_eCubeRole) && s_enabled;
    bool isMaster = G(IS_MASTER);
    std::string myip = G(MGMT_ADDR);

    WriteConfig(s_ha, s_hostname, myip, s_ctrlAddrs);

    SetupCheck();
    if (s_ha && (!s_bSetup || s_bForceNew))
        SetupCluster(enabled, isMaster, s_bForceNew, s_ctrlAddrs);
    else {
        if (!SystemdCommitService(enabled, NAME, true)) {
            if (s_ha) {
                SetupCluster(enabled, isMaster, true, s_ctrlAddrs);
            }
        }
    }

    WriteLogRotateConf(log_conf);

    if (!UpdateCheck())
        return false;

    // wait for rsync is done and service is ready for use
    if (enabled) {
        HexUtilSystemF(0, 0, HEX_SDK " wait_for_service %s 3306 90", myip.c_str());
    }

    CuratorCronJob(s_curatorRp.newValue());

    return true;
}

static bool
MigratePrepare(const char * prevVersion, const char * prevRootDir)
{
    HexSpawn(0, "/bin/mv", DATADIR, BACKDIR, NULL);
    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_mysql\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    bool enabled = IsControl(s_eCubeRole) && s_enabled;
    bool isMaster = G(IS_MASTER);
    std::string myip = G(MGMT_ADDR);

    SetupCheck();
    if (s_ha && s_bForceNew)
        SetupCluster(enabled, isMaster, s_bForceNew, s_ctrlAddrs);
    else {
        SystemdCommitService(enabled, NAME, false);
    }

    return EXIT_SUCCESS;
}

static int
SnapshotCreate(const char* snapdir)
{
    HexSystemF(0, HEX_SDK " support_mysql_backup_create %s/mnt/cephfs/backup", snapdir);
    return 0;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_mysql, RestartMain, RestartUsage);

CONFIG_MODULE(mysql, 0, Parse, 0, 0, Commit);
CONFIG_REQUIRES(mysql, cube_scan);

// extra tunings
CONFIG_OBSERVES(mysql, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(mysql, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(mysql, MigratePrepare);
CONFIG_MIGRATE(mysql, SETUP_MARK);
CONFIG_MIGRATE(mysql, "/var/lib/mysql");

CONFIG_SUPPORT_COMMAND(HEX_SDK " mysql_stats");

CONFIG_SNAPSHOT_COMMAND(mysql_backup_create, SnapshotCreate, 0, 0);

