// CUBE SDK

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <hex/log.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <hex/filesystem.h>
#include <hex/logrotate.h>
#include <hex/parse.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <cube/systemd_util.h>
#include <cluster.hpp>

#include "include/role_cubesys.h"

const static char NAME[] = "grafana-server";
const static char CONF[] = "/etc/grafana/grafana.ini";
const static char DB[] = "/var/lib/grafana/grafana.db";

// Salted with the cluster seed like the other service passwords, so every node of a
// cluster gets the same admin password and no two clusters share one.
static const char ADMINPASS[] = "4z8VFo5Sj2h0WU8B";
// No '#' or ';', which start a comment in grafana.ini.
#define ADMIN_PASS_REGEX "^[A-Za-z0-9._~-]{8,}$"

// The paths grafana-server.service hands the server. The rpm keeps them on the command
// line, not in grafana.ini, so the cli needs them too or it opens a different database.
#define GRAFANA_CLI_PATHS                                       \
    "cfg:default.paths.data=/var/lib/grafana "                  \
    "cfg:default.paths.logs=/var/log/grafana "                  \
    "cfg:default.paths.plugins=/var/lib/grafana/plugins "       \
    "cfg:default.paths.provisioning=/etc/grafana/provisioning"

static CubeRole_e s_eCubeRole;

static bool s_bCubeModified = false;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("grafana", "/var/log/grafana/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// private tunings
CONFIG_TUNING_STR(GRAFANA_ADMIN_PASS, "grafana.admin.password", TUNING_UNPUB,
                  "Set grafana admin password.", ADMINPASS, ValidateRegex, ADMIN_PASS_REGEX);

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);

// parse tunings
PARSE_TUNING_STR(s_adminPass, GRAFANA_ADMIN_PASS);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_BOOL(s_saltkey, CUBESYS_SALTKEY, 1);

static bool
WriteConfig(const std::string& sharedId, const std::string& adminPass)
{
    FILE *fout = fopen(CONF, "w");
    if (!fout) {
        HexLogError("Unable to write %s config: %s", NAME, CONF);
        return false;
    }

    // it carries the admin password from here on
    fchmod(fileno(fout), 0640);

    fprintf(fout, "[server]\n");
    // only haproxy talks to grafana, which serves it as /grafana on the shared id
    fprintf(fout, "http_addr = 127.0.0.1\n");
    fprintf(fout, "root_url = http://%s/grafana\n", sharedId.c_str());
    fprintf(fout, "\n");
    fprintf(fout, "[security]\n");
    fprintf(fout, "allow_embedding = true\n");
    // only seeds a new database; an existing one is reset in Commit()
    fprintf(fout, "admin_password = %s\n", adminPass.c_str());
    fprintf(fout, "\n");
    fprintf(fout, "[users]\n");
    fprintf(fout, "default_theme = light\n");
    fprintf(fout, "\n");
    fprintf(fout, "[auth]\n");
    fprintf(fout, "disable_login_form = true\n");
    fprintf(fout, "\n");
    // With the login form off as well, the admin password is of no use over the network;
    // admin work is done with grafana cli on the node.
    fprintf(fout, "[auth.basic]\n");
    fprintf(fout, "enabled = false\n");
    fprintf(fout, "\n");
    // The ceph dashboard embeds grafana panels in the browser, without a grafana session,
    // so read-only anonymous access stays. It is the Viewer role, never Admin.
    fprintf(fout, "[auth.anonymous]\n");
    fprintf(fout, "enabled = true\n");
    fprintf(fout, "#org_role = Admin\n");

    fclose(fout);

    HexSetFileMode(CONF, "root", "grafana", 0640);

    return true;
}

// grafana only reads admin_password when it creates its database, so a database that
// already exists keeps whatever admin password it had until it is reset. The password is
// fed on stdin from a root-only file, so it never shows up in a process list or the log.
static void
ResetAdminPass(const std::string& pass)
{
    char tmp[] = "/run/grafana-admin.XXXXXX";
    int fd = mkstemp(tmp);
    if (fd < 0) {
        HexLogWarning("Unable to reset %s admin password: %s", NAME, strerror(errno));
        return;
    }

    std::string line = pass + "\n";
    bool ok = write(fd, line.c_str(), line.size()) == (ssize_t)line.size();
    close(fd);

    if (ok) {
        int ret = HexUtilSystemF(FWD, 0,
                                 "timeout 60 runuser -u grafana -- grafana cli"
                                 " --homepath /usr/share/grafana --config %s"
                                 " --configOverrides \"" GRAFANA_CLI_PATHS "\""
                                 " admin reset-admin-password --password-from-stdin < %s",
                                 CONF, tmp);
        if (ret != 0)
            HexLogWarning("Unable to reset %s admin password (%d)", NAME, ret);
    } else {
        HexLogWarning("Unable to reset %s admin password: write %s failed", NAME, tmp);
    }

    unlink(tmp);
}

static bool
Parse(const char *name, const char *value, bool isNew)
{
    bool r = true;

    TuneStatus s = ParseTune(name, value, isNew);
    if (s == TUNE_INVALID_NAME) {
        HexLogWarning("Unknown settings name \"%s\" = \"%s\" ignored", name, value);
    } else if (s == TUNE_INVALID_VALUE) {
        HexLogError("Invalid settings value \"%s\" = \"%s\"", name, value);
        r = false;
    }
    return r;
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

    bool enabled = IsControl(s_eCubeRole);
    std::string sharedId = G(SHARED_ID);

    std::string adminPass = GetSaltKey(s_saltkey, s_adminPass, s_seed);
    if (adminPass.empty()) {
        HexLogError("Unable to derive %s admin password", NAME);
        return false;
    }

    struct stat ms;
    bool hasDb = stat(DB, &ms) == 0;

    WriteConfig(sharedId, adminPass);

    // with the server stopped, so nothing else has the database open
    if (enabled && hasDb) {
        HexUtilSystemF(FWD, 0, "systemctl stop %s", NAME);
        ResetAdminPass(adminPass);
    }

    SystemdCommitService(enabled, NAME);

    return true;
}

CONFIG_MODULE(grafana, 0, Parse, 0, 0, Commit);

// startup sequence
CONFIG_REQUIRES(grafana, influxdb);

// extra tunings
CONFIG_OBSERVES(grafana, cubesys, ParseCube, NotifyCube);
