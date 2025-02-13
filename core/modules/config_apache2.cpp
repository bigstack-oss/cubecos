// CUBE

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/logrotate.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>
#include <cube/systemd_util.h>

#include "include/role_cubesys.h"

#define HTTP_PORT 8080

static const char NAME[] = "httpd";
static const char CONF[] = "/etc/httpd/conf/httpd.conf";
static const char ORIG[] = "/etc/httpd/conf/httpd.conf.orig";
static const char SITECONF[] = "/etc/httpd/conf.d/00-default.conf";
static const char STATUSCONF[] = "/etc/httpd/conf.d/server-status.conf";

static ConfigString s_hostname;

static bool s_bNetModified = false;
static bool s_bCubeModified = false;

static bool s_bSiteConfChanged = false;

static CubeRole_e s_eCubeRole;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("httpd", "/var/log/httpd/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// public tunings
CONFIG_TUNING_BOOL(APACHE_DEBUG_ENABLED, "apache.debug.enabled", TUNING_UNPUB, "Set to true to enable apache debug logs.", false);

// private tunings
CONFIG_TUNING_BOOL(APACHE_ENABLED, "apache.enabled", TUNING_UNPUB, "Set to true to enable apache (web) service.", true);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);

// parse tunings
PARSE_TUNING_BOOL(s_debugEnabled, APACHE_DEBUG_ENABLED);
PARSE_TUNING_BOOL(s_enabled, APACHE_ENABLED);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);

static bool
WriteSiteConf(const char* hostname, const bool debug)
{
    FILE *fout = fopen(SITECONF, "w");
    if (!fout) {
        HexLogFatal("Unable to write default site file: %s", SITECONF);
        return false;
    }

    fprintf(fout, "ServerName %s\n", hostname);
    fprintf(fout, "ErrorLog /var/log/httpd/error.log\n");
    fprintf(fout, "CustomLog /var/log/httpd/access.log combined\n");
    fprintf(fout, "LogLevel %s\n", debug ? "debug" : "info");
    fprintf(fout, "<VirtualHost *:%d>\n", HTTP_PORT);
    fprintf(fout, "</VirtualHost>\n");

    fclose(fout);

    return true;
}

static bool
WriteStatusConf()
{
    FILE *fout = fopen(STATUSCONF, "w");
    if (!fout) {
        HexLogFatal("Unable to write server status config: %s", STATUSCONF);
        return false;
    }

    fprintf(fout, "<Location \"/server-status\">\n");
    fprintf(fout, "  SetHandler server-status\n");
    fprintf(fout, "  allow from localhost\n");
    fprintf(fout, "</Location>\n");

    fclose(fout);

    return true;
}

static bool
Init()
{
    if (HexSystemF(0, "sed -e \"s/Listen 80/Listen %d/\" %s > %s",
                      HTTP_PORT, ORIG, CONF) != 0) {
        HexLogError("failed to update %s", CONF);
        return false;
    }

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
NotifyNet(bool modified)
{
    s_bNetModified = s_hostname.modified();
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
        s_bSiteConfChanged = true;
        return true;
    }

    s_bSiteConfChanged = modified | s_bNetModified;

    return s_bSiteConfChanged | G_MOD(SHARED_ID);
}

static bool
Commit(bool modified, int dryLevel)
{
    // TODO: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    char buf[256];

    if (!IsControl(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    std::string sharedId = G(SHARED_ID);

    WriteStatusConf();

    if (s_bSiteConfChanged)
        WriteSiteConf(s_hostname.c_str(), s_debugEnabled.newValue());

    bool enabled = s_enabled && IsControl(s_eCubeRole);
    SystemdCommitService(enabled, NAME);

    // waiting for keystone endpoint service back to work
    if (enabled && HexUtilSystemF(0, 0, HEX_SDK " wait_for_http_endpoint %s 5000 60", sharedId.c_str()) != 0) {
        return false;
    }

    snprintf(buf, sizeof(buf),
            "/bin/systemctl reload httpd.service > /dev/null 2>/dev/null || true");
    log_conf.postRotateCmds = buf;
    WriteLogRotateConf(log_conf);

    return true;
}

CONFIG_MODULE(apache2, Init, Parse, 0, 0, Commit);

// startup sequence
CONFIG_REQUIRES(apache2, glance);
CONFIG_REQUIRES(apache2, nova);
CONFIG_REQUIRES(apache2, neutron);
CONFIG_REQUIRES(apache2, cinder);
CONFIG_REQUIRES(apache2, manila);
CONFIG_REQUIRES(apache2, swift);
CONFIG_REQUIRES(apache2, horizon);
CONFIG_REQUIRES(apache2, heat);
CONFIG_REQUIRES(apache2, barbican);
CONFIG_REQUIRES(apache2, monasca);
CONFIG_REQUIRES(apache2, masakari);
// CONFIG_REQUIRES(apache2, keystone_idp);

// extra tunings
CONFIG_OBSERVES(apache2, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(apache2, cubesys, ParseCube, NotifyCube);

