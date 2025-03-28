#include <unistd.h>
#include <sstream>
#include <hex/log.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>
#include <hex/process_util.h>
#include <hex/dryrun.h>

#include <cube/cluster.h>

static const char KEYCLOAK_VALUES_CHART[] = "/opt/keycloak/chart-values.yaml";

static bool s_bApplianceModified = false;

CONFIG_GLOBAL_BOOL_REF(IS_MASTER);

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

    bool isMaster = G(IS_MASTER);
    if (!isMaster) {
        // only the master node is allowed to modify keycloak
        // to prevent nodes from tripping over each others'
        // keycloak bootstrap process during bootstrapping
        return true;
    }

    if (IsBootstrap()) {
        // destroy the running keycloak
        HexUtilSystemF(0, 0, "cubectl config reset keycloak --stacktrace");
    }

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

        // destroy the running keycloak
        HexUtilSystemF(0, 0, "cubectl config reset keycloak --stacktrace");
    }

    // restart keycloak
    // placed here for bootstrapping, if one is already running, this is a no-op
    return HexUtilSystemF(0, 0, "cubectl config commit keycloak --stacktrace") == 0;
}

CONFIG_MODULE(keycloak, 0, 0, 0, 0, Commit);

// startup sequence
CONFIG_REQUIRES(keycloak, cube_scan);
CONFIG_REQUIRES(keycloak, k3s);
CONFIG_REQUIRES(keycloak, mysql);

// tuning dependencies
CONFIG_OBSERVES(keycloak, appliance, ParseAppliance, NotifyAppliance);

CONFIG_MIGRATE(keycloak, "/etc/keycloak");
