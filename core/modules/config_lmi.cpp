// CUBE

#include <list>

#include <hex/log.h>
#include <hex/pidfile.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/logrotate.h>
#include <hex/filesystem.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/dryrun.h>

#include <cube/cluster.h>
#include <cube/systemd_util.h>

#include "include/role_cubesys.h"

#define MARKER_LMI_IDP  "/etc/appliance/state/lmi_idp_done"
#define CLUSTER_LIST    "/var/appliance-db/cluster.lst"
#define APP_LIST        "/var/appliance-db/app.lst"

const static char USER[] = "www-data";
const static char GROUP[] = "www-data";

static const char NAME[] = "lmi";
static const char SERVER_ENV[] = "/var/www/lmi/.env";
static const char CLIENT_ENV[] = "/var/www/lmi/static/env.js";

static bool s_bCubeModified = false;
static bool s_bRancherModified = false;
static bool s_bApplianceModified = false;

static CubeRole_e s_eCubeRole;

// rotate daily and enable copytruncate
static LogRotateConf log_conf("lmi", "/var/www/lmi/*.log", DAILY, 128, 0, true);

// external global variables
CONFIG_GLOBAL_STR_REF(SHARED_ID);
CONFIG_GLOBAL_STR_REF(EXTERNAL);

// private tunings
CONFIG_TUNING_BOOL(LMI_ENABLED, "lmi.enabled", TUNING_UNPUB, "Set to true to enable lmi.", true);

// using external tunings
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_REGION);
CONFIG_TUNING_SPEC_BOOL(RANCHER_ENABLED);
CONFIG_TUNING_SPEC_STR(APPLIANCE_LOGIN_GREETING);

// parse tunings
PARSE_TUNING_BOOL(s_enabled, LMI_ENABLED);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 1);
PARSE_TUNING_X_BOOL(s_rancherEnabled, RANCHER_ENABLED, 2);
PARSE_TUNING_X_STR(s_loginGreeting, APPLIANCE_LOGIN_GREETING, 3);

struct ClusterInfo {
    std::string name;
    std::string cluster;
    std::string iam_admin_url;
    std::string iam_user_url;
    std::string iaas_url;
    std::string k8s_url;
    std::string storage_url;
    std::string portal_url;
    std::string apigw_url;
    std::string local;
};

std::list<ClusterInfo> ClusterList;

struct AppInfo {
    std::string name;
    std::string link;
    std::string image;
};

std::map<std::string, std::list<AppInfo>> AppMap;

static void
ItemInfoGet(const std::string &line, const std::string &key, std::string *value)
{
    size_t found;
    *value = "";

    if (line.find(key) != std::string::npos) {
        *value = line.substr(line.find(key) + strlen(key.c_str()));
        found = value->find(',');
        if (found != std::string::npos)
           value->erase(found, std::string::npos);  // get rid of rest after comma
        found = value->find('\n');
        if (found != std::string::npos)
           value->erase(found, std::string::npos);  // get rid of rest after newline
        found = value->find('\r');
        if (found != std::string::npos)
           value->erase(found, std::string::npos);  // get rid of rest after return
    }
}

static const std::string
EscapeSingleQuote(const std::string &str)
{
    // 1. Escape each single quoat(") to '\"'
    std::stringstream out;
    for (std::string::const_iterator it = str.begin(); it != str.end(); it++) {
        if (*it == '\'')
            out << "\\\'";
        else
            out << *it;
    }
    return out.str();
}

static bool
WriteClientEnv(const std::string &external, bool rancherEnabled, const std::string &greeting)
{
    FILE *fout = fopen(CLIENT_ENV, "w");
    if (!fout) {
        HexLogError("Unable to write %s client env: %s", NAME, CLIENT_ENV);
        return false;
    }

    fprintf(fout, "window.env = {\n");
    fprintf(fout, "  EDGE_CORE: %s,\n", IsCore(s_eCubeRole) ? "true" : "false");
    fprintf(fout, "  RANCHER: %s,\n", rancherEnabled ? "true" : "false");
    fprintf(fout, "  LOGIN_GREETING: '%s',\n", EscapeSingleQuote(greeting).c_str());
    fprintf(fout, "};\n");

    fprintf(fout, "window.cluster = {\n");

    if (access(CLUSTER_LIST, F_OK) == 0) {
        ClusterList.clear();

        FILE *fin = fopen(CLUSTER_LIST, "r");
        if (!fin) {
            HexLogError("Unable to read cluster list: %s", CLUSTER_LIST);
            return false;
        }

        char *buffer = NULL;
        size_t bufSize = 0;
        while (getline(&buffer, &bufSize, fin) > 0) {
            std::string line = buffer;

            ClusterInfo info;
            ItemInfoGet(line, "name=", &info.name);
            ItemInfoGet(line, "cluster=", &info.cluster);
            ItemInfoGet(line, "iam_admin_url=", &info.iam_admin_url);
            ItemInfoGet(line, "iam_user_url=", &info.iam_user_url);
            ItemInfoGet(line, "iaas_url=", &info.iaas_url);
            ItemInfoGet(line, "k8s_url=", &info.k8s_url);
            ItemInfoGet(line, "storage_url=", &info.storage_url);
            ItemInfoGet(line, "portal_url=", &info.portal_url);
            ItemInfoGet(line, "apigw_url=", &info.apigw_url);
            ItemInfoGet(line, "local=", &info.local);
            ClusterList.push_back(info);
        }

        free(buffer);
        buffer = NULL;

        fclose(fin);

        for (auto const& info : ClusterList) {
            // write an additional local object as default
            if (info.local == "true") {
                fprintf(fout, "  local: {\n");
                fprintf(fout, "    API_URL: 'https://%s',\n", info.cluster.c_str());
                fprintf(fout, "    CUBE_URL: '%s',\n", info.cluster.c_str());
                if (info.iam_admin_url.length() > 0)
                    fprintf(fout, "    IAM_ADMIN_URL: '%s',\n", info.iam_admin_url.c_str());
                if (info.iam_user_url.length() > 0)
                    fprintf(fout, "    IAM_USER_URL: '%s',\n", info.iam_user_url.c_str());
                if (info.iaas_url.length() > 0)
                    fprintf(fout, "    IAAS_URL: '%s',\n", info.iaas_url.c_str());
                if (info.k8s_url.length() > 0)
                    fprintf(fout, "    K8S_URL: '%s',\n", info.k8s_url.c_str());
                if (info.storage_url.length() > 0)
                    fprintf(fout, "    STORAGE_URL: '%s',\n", info.storage_url.c_str());
                if (info.portal_url.length() > 0)
                    fprintf(fout, "    PORTAL_URL: '%s',\n", info.portal_url.c_str());
                if (info.apigw_url.length() > 0)
                    fprintf(fout, "    API_GW_URL: '%s',\n", info.apigw_url.c_str());
                fprintf(fout, "    LOCAL: true,\n");
                fprintf(fout, "  },\n");
            }

            fprintf(fout, "  '%s': {\n", info.name.c_str());
            fprintf(fout, "    API_URL: 'https://%s',\n", info.cluster.c_str());
            fprintf(fout, "    CUBE_URL: '%s',\n", info.cluster.c_str());
            if (info.iam_admin_url.length() > 0)
                fprintf(fout, "    IAM_ADMIN_URL: '%s',\n", info.iam_admin_url.c_str());
            if (info.iam_user_url.length() > 0)
                fprintf(fout, "    IAM_USER_URL: '%s',\n", info.iam_user_url.c_str());
            if (info.iaas_url.length() > 0)
                fprintf(fout, "    IAAS_URL: '%s',\n", info.iaas_url.c_str());
            if (info.k8s_url.length() > 0)
                fprintf(fout, "    K8S_URL: '%s',\n", info.k8s_url.c_str());
            if (info.storage_url.length() > 0)
                fprintf(fout, "    STORAGE_URL: '%s',\n", info.storage_url.c_str());
            if (info.portal_url.length() > 0)
                fprintf(fout, "    PORTAL_URL: '%s',\n", info.portal_url.c_str());
            if (info.apigw_url.length() > 0)
                fprintf(fout, "    API_GW_URL: '%s',\n", info.apigw_url.c_str());
            fprintf(fout, "    LOCAL: %s,\n", info.local.length() ? info.local.c_str() : "false");
            fprintf(fout, "  },\n");
        }

    }
    else {
        fprintf(fout, "  local: {\n");
        fprintf(fout, "    API_URL: 'https://%s',\n", external.c_str());
        fprintf(fout, "    CUBE_URL: '%s',\n", external.c_str());
        fprintf(fout, "    LOCAL: true,\n");
        fprintf(fout, "  },\n");
    }

    fprintf(fout, "};\n");

    if (access(APP_LIST, F_OK) == 0) {
        AppMap.clear();

        FILE *fin = fopen(APP_LIST, "r");
        if (!fin) {
            HexLogError("Unable to read app list: %s", APP_LIST);
            return false;
        }

        char *buffer = NULL;
        size_t bufSize = 0;
        while (getline(&buffer, &bufSize, fin) > 0) {
            std::string line = buffer;

            std::string group;
            AppInfo info;
            ItemInfoGet(line, "group=", &group);
            ItemInfoGet(line, "name=", &info.name);
            ItemInfoGet(line, "link=", &info.link);
            ItemInfoGet(line, "image=", &info.image);
            AppMap[group].push_back(info);
        }

        free(buffer);
        buffer = NULL;

        fclose(fin);

        fprintf(fout, "window.app = {\n");
        for (auto const& [group, list] : AppMap) {
            fprintf(fout, "  '%s': [\n", group.c_str());
            for(const auto& info : list) {
                if (info.name.length() <= 0)
                    continue;

                fprintf(fout, "    {\n");
                fprintf(fout, "      NAME: '%s',\n", info.name.c_str());
                fprintf(fout, "      LINK: '%s',\n", info.link.c_str());
                fprintf(fout, "      IMAGE: '%s',\n", info.image.c_str());
                fprintf(fout, "    },\n");
            }
            fprintf(fout, "  ],\n");
        }

        fprintf(fout, "};\n");
    }
    else {
        fprintf(fout, "window.app = {};\n");
    }

    fclose(fout);

    HexSetFileMode(CLIENT_ENV, "www-data", "www-data", 0644);

    return true;
}

static bool
WriteServerEnv(const std::string &sharedId)
{
    FILE *fout = fopen(SERVER_ENV, "w");
    if (!fout) {
        HexLogError("Unable to write %s server env: %s", NAME, SERVER_ENV);
        return false;
    }

    std::string idpCert = HexUtilPOpen("grep -oP '(?<=ds:X509Certificate>)[^<]+' /etc/keycloak/saml-metadata.xml");

    fprintf(fout, "NODE_ENV=production\n");
    fprintf(fout, "PORT=8081\n");
    fprintf(fout, "SAML_SP_URL=https://%s\n", sharedId.c_str());
    fprintf(fout, "SAML_IDP_URL=https://%s:10443\n", sharedId.c_str());
    fprintf(fout, "SAML_IDP_CERT=%s\n", idpCert.c_str());

    fclose(fout);

    HexSetFileMode(SERVER_ENV, "www-data", "www-data", 0644);

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
ParseRancher(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 2);
    return true;
}

static void
NotifyRancher(bool modified)
{
    s_bRancherModified = IsModifiedTune(2);
}

static bool
ParseAppliance(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 3);
    return true;
}

static void
NotifyAppliance(bool modified)
{
    s_bApplianceModified = IsModifiedTune(3);
}

static bool
CommitCheck(bool modified, int dryLevel)
{
    if (IsBootstrap()) {
        return true;
    }

    return modified | s_bCubeModified | s_bRancherModified | s_bApplianceModified | G_MOD(SHARED_ID) | G_MOD(EXTERNAL);
}

static bool
Commit(bool modified, int dryLevel)
{
    // todo: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (IsUndef(s_eCubeRole) || !CommitCheck(modified, dryLevel))
        return true;

    bool enabled = IsControl(s_eCubeRole) & s_enabled;
    std::string sharedId = G(SHARED_ID);
    std::string external = G(EXTERNAL);

    if (IsControl(s_eCubeRole)) {
        WriteLogRotateConf(log_conf);
        WriteServerEnv(sharedId);
        WriteClientEnv(external, s_rancherEnabled, s_loginGreeting);
        if (access(MARKER_LMI_IDP, F_OK) != 0) {
            HexUtilSystemF(0, 0, HEX_SDK " lmi_idp_config %s", sharedId.c_str());
            HexSystemF(0, "touch %s", MARKER_LMI_IDP);
        }
    }

    SystemdCommitService(enabled, NAME);

    return true;
}

static void
RestartUsage(void)
{
    fprintf(stderr, "Usage: %s restart_lmi\n", HexLogProgramName());
}

static int
RestartMain(int argc, char* argv[])
{
    if (argc != 1) {
        RestartUsage();
        return EXIT_FAILURE;
    }

    bool enabled = IsControl(s_eCubeRole) & s_enabled;
    SystemdCommitService(enabled, NAME);

    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(restart_lmi, RestartMain, RestartUsage);

CONFIG_MODULE(lmi, 0, Parse, 0, 0, Commit);
// startup sequence
CONFIG_REQUIRES(lmi, net_static);
CONFIG_REQUIRES(lmi, keycloak);

// extra tunings
CONFIG_OBSERVES(lmi, cubesys, ParseCube, NotifyCube);
CONFIG_OBSERVES(lmi, rancher, ParseRancher, NotifyRancher);
CONFIG_OBSERVES(lmi, appliance, ParseAppliance, NotifyAppliance);

CONFIG_MIGRATE(lmi, "/var/www/lmi/server.log");
CONFIG_MIGRATE(lmi, CLUSTER_LIST);
CONFIG_MIGRATE(lmi, APP_LIST);

