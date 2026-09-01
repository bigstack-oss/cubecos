// CUBE SDK

#include "include/role_cubesys.h"

#include <cube/systemd_util.h>
#include <filesystem.hpp>
#include <hex/config_global.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/dryrun.h>
#include <hex/log.h>
#include <hex/logrotate.h>
#include <hex/pidfile.h>
#include <hex/process.h>
#include <hex/process_util.h>

// httpd's only consumers are local: haproxy's openstack_horizon backend and the
// monasca agent's server-status check. Binding loopback keeps 8080 off the
// management network, where vulnerability scanners were reaching it.
#define HTTP_ADDR "127.0.0.1"
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
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// public tunings
CONFIG_TUNING_BOOL(APACHE_DEBUG_ENABLED, "apache.debug.enabled", TUNING_UNPUB, "Set to true to enable apache debug logs.", false);

// private tunings
CONFIG_TUNING_BOOL(APACHE_ENABLED, "apache.enabled", TUNING_UNPUB, "Set to true to enable apache (web) service.", true);

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);

// parse tunings
PARSE_TUNING_BOOL(s_debugEnabled, APACHE_DEBUG_ENABLED);
PARSE_TUNING_BOOL(s_enabled, APACHE_ENABLED);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);

static bool
WriteSiteConf(const char* hostname, const bool debug)
{
    const std::vector<std::string> fileContent = {
        std::string("ServerName ") + hostname + "\n",
        "ErrorLog /var/log/httpd/error.log\n",
        "CustomLog /var/log/httpd/access.log combined\n",
        std::string("LogLevel ") + (debug ? "debug" : "info") + "\n",

        // Suppress the version banner here rather than relying on
        // keystone's ssl.conf, which also sets these. Same values, so the
        // duplication is inert.
        "ServerTokens Prod\n",
        "ServerSignature Off\n",
        "TraceEnable Off\n",

        // Stock httpd.conf grants Indexes on the DocumentRoot, and welcome.conf
        // (removed from the image) carried the only "Options -Indexes" covering
        // "/". DocumentRoot holds nothing -- /var/www is used for certs only --
        // so deny it outright and serve a bare 403.
        "<Directory \"/var/www/html\">\n",
        "    Options -Indexes\n",
        "    AllowOverride None\n",
        "    Require all denied\n",
        "</Directory>\n",

        std::string("<VirtualHost *:") + std::to_string(HTTP_PORT) + ">\n",
        "</VirtualHost>\n",
    };

    std::string fsError;
    if (!WriteFile(
            fsError,
            SITECONF,
            fileContent)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    return true;
}

/**
 * Write Apache mod_status server-status config for non-HA nodes.
 */
static bool
writeStatusConf(const std::string& myIp)
{
    const std::vector<std::string> fileContent = {
        "<Location \"/server-status\">\n",
        "  SetHandler server-status\n",

        // ban all requests to mitigate Apache mod_status information disclosure vulnerability
        "  Require all denied\n",

        // allow Monasca agents to access
        "  Require local\n",
        "  Require ip " + myIp + "\n",
        "</Location>\n",
    };

    std::string fsError;
    if (!WriteFile(
            fsError,
            STATUSCONF,
            fileContent)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    return true;
}

/**
 * Write Apache mod_status server-status config for HA clusters.
 */
static bool
writeStatusConf(const std::vector<std::string>& controlIps)
{
    std::vector<std::string> fileContent = {
        "<Location \"/server-status\">\n",
        "  SetHandler server-status\n",

        // ban all requests to mitigate Apache mod_status information disclosure vulnerability
        "  Require all denied\n",
    };

    // allow Monasca agents to access
    fileContent.push_back("  Require local\n");
    for (std::vector<std::string>::const_iterator it = controlIps.begin(); it != controlIps.end(); it++) {
        fileContent.push_back("  Require ip " + (*it) + "\n");
    }

    fileContent.push_back("</Location>\n");

    std::string fsError;
    if (!WriteFile(
            fsError,
            STATUSCONF,
            fileContent)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    return true;
}

static bool
Init()
{
    if (HexSystemF(
            0,
            "sed -e \"s/Listen 80/Listen %s:%d/\" %s > %s",
            HTTP_ADDR,
            HTTP_PORT,
            ORIG,
            CONF)
        != 0) {
        HexLogError("failed to update %s", CONF);
        return false;
    }

    return true;
}

static bool
Parse(const char* name, const char* value, bool isNew)
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
ParseNet(const char* name, const char* value, bool isNew)
{
    if (strcmp(name, NET_HOSTNAME) == 0) {
        s_hostname.parse(value, isNew);
    }

    return true;
}

static bool
ParseCube(const char* name, const char* value, bool isNew)
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

    if (s_bSiteConfChanged) {
        WriteSiteConf(s_hostname.c_str(), s_debugEnabled.newValue());
    }

    if (s_ha.modified() || s_ctrlAddrs.modified() || G_MOD(MGMT_ADDR)) {
        if (s_ha) {
            const std::vector<std::string> controlIps = hex_string_util::split(s_ctrlAddrs, ',');
            writeStatusConf(controlIps);
        } else {
            const std::string myIp = G(MGMT_ADDR);
            writeStatusConf(myIp);
        }
    }

    bool enabled = s_enabled && IsControl(s_eCubeRole);
    SystemdCommitService(enabled, NAME);

    // waiting for keystone endpoint service back to work; 600 is now real
    // seconds, not attempts (~377s measured on a cold boot)
    std::string sharedId = G(SHARED_ID);
    if (enabled && HexUtilSystemF(0, 0, HEX_SDK " wait_for_http_endpoint %s 5000 600", sharedId.c_str()) != 0) {
        return false;
    }

    snprintf(
        buf,
        sizeof(buf),
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
