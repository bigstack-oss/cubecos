#include <unistd.h>
#include <sstream>
#include <hex/log.h>
#include <hex/config_global.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/process_util.h>
#include <hex/dryrun.h>

#include <cube/cluster.h>

#define KEYCLOAK_SAML_METADATA_FILE "/etc/keycloak/saml-metadata.xml"
#define KEYCLOAK_SAML_METADATA_FILE_TMP "/tmp/keycloak-saml-metadata.xml"

static const char KEYCLOAK_VALUES_CHART[] = "/opt/keycloak/chart-values.yaml";

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);

static bool s_bApplianceModified = false;

// using external tunings
CONFIG_TUNING_SPEC_STR(APPLIANCE_LOGIN_GREETING);

// parse tunings
PARSE_TUNING_STR(s_loginGreeting, APPLIANCE_LOGIN_GREETING);

static bool
ParseAppliance(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 0);
    return true;
}

static void
NotifyAppliance(bool modified)
{
    s_bApplianceModified = IsModifiedTune(0);
}

static const std::string
EscapeQuote(const std::string &str)
{
    std::stringstream out;
    for (std::string::const_iterator it = str.begin(); it != str.end(); it++) {
        if (*it == '\"') {
            // escape each double quoat(") to \\\",
            // need to do so cuz sed and yaml both collapse the escape characters
            out << "\\\\\\\"";
        } else if (*it == '\'') {
            // escape each single quoat(') to '"\'"',
            // need to do so cuz we use single quoted string for sed,
            // only way to escape this, is to concatenate them
            out << "'\"\\'\"'";
        } else {
            out << *it;
        }
    }
    return out.str();
}

static bool
Commit(bool modified, int dryLevel)
{
    // TODO: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (s_bApplianceModified) {
        if (access(KEYCLOAK_VALUES_CHART, F_OK) != 0) {
            HexLogError("Unable to write the login greeting message to %s", KEYCLOAK_VALUES_CHART);
            return false;
        }
    
        if (s_loginGreeting.empty()) {
            // remove the login greeting message from keycloak helm values chart
            HexUtilSystemF(0, 0, "sed -i '/LOGIN_GREETING/{n;s/value:.*/value:/}' %s", KEYCLOAK_VALUES_CHART);
        } else {
            // inject the login greeting message to keycloak through the helm values chart
            HexUtilSystemF(0, 0, "sed -i '/LOGIN_GREETING/{n;s/value:.*/value: \"%s\"/}' %s", EscapeQuote(s_loginGreeting).c_str(), KEYCLOAK_VALUES_CHART);
        }

        // should not destroy keycloak during node level bootstrapping
        // since we could not get keycloak back on the master node when etcd quorum is not ready
        if (!IsBootstrap()) {
            // destroy the running keycloak
            HexUtilSystemF(0, 0, "cubectl config reset keycloak --stacktrace");
        }
    }

    // restart keycloak
    HexUtilSystemF(0, 0, "cubectl config commit keycloak --stacktrace");
    return true;
}

static int
ClusterStartMain(int argc, char **argv)
{
    if (argc != 1) {
        return EXIT_FAILURE;
    }

    // destroy the running keycloak
    HexUtilSystemF(0, 0, "cubectl config reset keycloak --stacktrace");
    // restart keycloak
    HexUtilSystemF(0, 0, "cubectl config commit keycloak --stacktrace");

    // sync saml-metadata.xml
    std::string myip = G(MGMT_ADDR);
    if (access(KEYCLOAK_SAML_METADATA_FILE, F_OK) == 0) {
        HexUtilSystemF(0, 0, "cp -f %s %s", KEYCLOAK_SAML_METADATA_FILE, KEYCLOAK_SAML_METADATA_FILE_TMP);
        HexUtilSystemF(0, 0, "cubectl node exec -r control -p scp root@%s:%s %s", myip.c_str(), KEYCLOAK_SAML_METADATA_FILE_TMP, KEYCLOAK_SAML_METADATA_FILE);
        unlink(KEYCLOAK_SAML_METADATA_FILE_TMP);
    } else {
        HexLogError("%s is missing on %s", KEYCLOAK_SAML_METADATA_FILE, myip.c_str());
    }
    return EXIT_SUCCESS;
}

CONFIG_MODULE(keycloak, 0, 0, 0, 0, Commit);

// startup sequence
CONFIG_REQUIRES(keycloak, cube_scan);
CONFIG_REQUIRES(keycloak, k3s);
CONFIG_REQUIRES(keycloak, mysql);

// tuning dependencies
CONFIG_OBSERVES(keycloak, appliance, ParseAppliance, NotifyAppliance);

CONFIG_MIGRATE(keycloak, "/etc/keycloak");

CONFIG_TRIGGER_WITH_SETTINGS(keycloak, "cluster_start", ClusterStartMain);
