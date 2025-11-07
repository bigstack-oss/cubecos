// CUBE SDK

#include "config_keycloak.hpp"

static const char KEYCLOAK_CHART_VALUES[] = "/opt/keycloak/chart-values.yaml";
static const std::string APP = "statefulset.apps/keycloak";
static std::string APP_NAMESPACE = "keycloak";

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);

// using external tunings
CONFIG_TUNING_SPEC_STR(APPLIANCE_LOGIN_GREETING);

// parse tunings
PARSE_TUNING_STR(s_loginGreeting, APPLIANCE_LOGIN_GREETING);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);

static bool s_bApplianceModified = false;
static bool s_bCubeModified = false;

static CubeRole_e s_eCubeRole;

static bool
ParseAppliance(const char* name, const char* value, bool isNew)
{
    ParseTune(name, value, isNew, 0);
    return true;
}

static void
NotifyAppliance(bool modified)
{
    s_bApplianceModified = IsModifiedTune(0);
}

static bool
ParseCube(const char* name, const char* value, bool isNew)
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

static const std::string
escapeQuote(const std::string& str)
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
updateKeycloakChartValues(const std::string loginGreeting)
{
    HexLogInfo("update %s", KEYCLOAK_CHART_VALUES);
    if (access(KEYCLOAK_CHART_VALUES, F_OK) != 0) {
        HexLogError("failed to access %s", KEYCLOAK_CHART_VALUES);
        return false;
    }

    int ret = 0;

    if (loginGreeting.empty()) {
        // remove the login greeting message from keycloak helm values chart
        ret = HexUtilSystemF(
            0,
            0,
            "sed -i '/LOGIN_GREETING/{n;s/value:.*/value:/}' %s",
            KEYCLOAK_CHART_VALUES);
    } else {
        // inject the login greeting message to keycloak through the helm values chart
        ret = HexUtilSystemF(
            0,
            0,
            "sed -i '/LOGIN_GREETING/{n;s/value:.*/value: \"%s\"/}' %s", escapeQuote(loginGreeting).c_str(),
            KEYCLOAK_CHART_VALUES);
    }

    if (ret == 0) {
        HexLogInfo("updated %s", KEYCLOAK_CHART_VALUES);
    } else {
        HexLogError("failed to update %s", KEYCLOAK_CHART_VALUES);
    }

    return (ret == 0);
}

static bool
Commit(bool modified, int dryLevel)
{
    // TODO: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (s_bApplianceModified) {
        if (!updateKeycloakChartValues(s_loginGreeting)) {
            HexLogError(
                "unable to write the login greeting message to %s",
                KEYCLOAK_CHART_VALUES);
            return false;
        }

        // should not destroy keycloak during node level bootstrapping
        // since we could not get keycloak back on the master node when etcd quorum is not ready
        if (!IsBootstrap()) {
            // destroy the running keycloak
            HexLogInfo("destroy keycloak");
            if (HexUtilSystemF(0, 0, "cubectl config reset keycloak --stacktrace") == 0) {
                HexLogInfo("destroyed keycloak");
            } else {
                HexLogError("failed to destroy keycloak");
            }
        }
    }

    // restart keycloak
    HexLogInfo("commit keycloak");
    if (HexUtilSystemF(0, 0, "cubectl config commit keycloak --stacktrace") == 0) {
        HexLogInfo("committed keycloak");
    } else {
        HexLogError("failed to commit keycloak");
    }
    return true;
}

static int
ClusterStartMain(int argc, char** argv)
{
    if (argc != 1) {
        return EXIT_FAILURE;
    }

    // destroy the running keycloak
    HexLogInfo("destroy keycloak");
    if (HexUtilSystemF(0, 0, "cubectl config reset keycloak --stacktrace") == 0) {
        HexLogInfo("destroyed keycloak");
    } else {
        HexLogError("failed to destroy keycloak");
    }
    // restart keycloak
    HexLogInfo("commit keycloak");
    if (HexUtilSystemF(0, 0, "cubectl config commit keycloak --stacktrace") == 0) {
        HexLogInfo("committed keycloak");
    } else {
        HexLogError("failed to commit keycloak");
    }

    // sync saml-metadata.xml
    std::string myip = G(MGMT_ADDR);
    if (access(KEYCLOAK_SAML_METADATA_FILE, F_OK) == 0) {
        HexLogInfo("sync the keycloak saml metadata file");

        HexUtilSystemF(0, 0, "cp -f %s %s", KEYCLOAK_SAML_METADATA_FILE, KEYCLOAK_SAML_METADATA_FILE_TMP);
        HexUtilSystemF(0, 0, "hex_sdk cmd -cv scp root@%s:%s %s", myip.c_str(), KEYCLOAK_SAML_METADATA_FILE_TMP, KEYCLOAK_SAML_METADATA_FILE);
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
CONFIG_OBSERVES(keycloak, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(keycloak, "/etc/keycloak");

CONFIG_TRIGGER_WITH_SETTINGS(keycloak, "cluster_start", ClusterStartMain);

static void
StatusKeycloakUsage(void)
{
    fprintf(stderr, "Usage: %s status_keycloak\n", HexLogProgramName());
}

static int
statusKeycloak()
{
    HexLogInfo("print keycloak status");
    return HexSpawn(0, "/usr/local/bin/k3s", "kubectl", "get", "all", "-n", "keycloak", "-o", "wide", NULL);
}

static int
StatusKeycloakMain(int argc, char** argv)
{
    return statusKeycloak();
}

CONFIG_COMMAND(status_keycloak, StatusKeycloakMain, StatusKeycloakUsage);

static void
CheckKeycloakUsage(void)
{
    fprintf(stderr, "Usage: %s check_keycloak\n", HexLogProgramName());
}

static bool
checkKeycloak()
{
    HexLogInfo("check keycloak");

    if (!K3sWatchRollOut(APP, APP_NAMESPACE, "1s")) {
        HexLogError("failed to see all pods rolled out");
        return false;
    }

    int nodeCount = K3sGetNodeCounts();
    if (nodeCount < 0) {
        HexLogError("failed to get the node count");
        return false;
    }

    int replicaCount = K3sGetReadyReplicas(APP, APP_NAMESPACE);
    if (replicaCount < 0) {
        HexLogError("failed to get the ready replica count");
        return false;
    }

    if (nodeCount != replicaCount) {
        HexLogError(
            "control node count: %d doesn't match replica count: %d",
            nodeCount,
            replicaCount);
        return false;
    }

    HexLogInfo("checked keycloak");
    return true;
}

static int
CheckKeycloakMain(int argc, char** argv)
{
    return checkKeycloak() ? EXIT_SUCCESS : EXIT_FAILURE;
}

CONFIG_COMMAND(check_keycloak, CheckKeycloakMain, CheckKeycloakUsage);

static void
RepairKeycloakUsage(void)
{
    fprintf(stderr, "Usage: %s repair_keycloak\n", HexLogProgramName());
}

static bool
repairKeycloak()
{
    if (!IsControl(s_eCubeRole)) {
        HexLogNotice("keycloak should not be repaired from a non-control node");
        return true;
    }

    if (!K3sDeleteAllPods(APP_NAMESPACE)) {
        HexLogError("failed to delete all pods of keycloak");
        return false;
    }

    if (!K3sWatchRollOut(APP, APP_NAMESPACE, "3m")) {
        HexLogError("failed to see all pods rolled out");
        return false;
    }

    return true;
}

static int
RepairKeycloakMain(int argc, char** argv)
{
    return repairKeycloak() ? EXIT_SUCCESS : EXIT_FAILURE;
}

CONFIG_COMMAND_WITH_SETTINGS(repair_keycloak, RepairKeycloakMain, RepairKeycloakUsage);
