// CUBE SDK

#include "config_keycloak.hpp"

static const std::string APP = "statefulset.apps/keycloak";
static const std::string APP_NAMESPACE = "keycloak";
static const std::string CHART_RELEASE_NAME = "keycloak";
static const char KEYCLOAK_CHARTS[] = "/opt/keycloak/keycloak-*.tgz";
static const char KEYCLOAK_CHART_VALUES[] = "/opt/keycloak/chart-values.yaml";
static const std::string DB_NAME = "keycloak";
static const char KEYCLOAK_SAML_METADATA_FILE[] = "/etc/keycloak/saml-metadata.xml";

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

/**
 * Check if the database is set up for Keycloak.
 */
static bool
isDatabaseSetup()
{
    return MysqlUtilIsDbExist("keycloak");
}

/**
 * Set up the database for Keycloak.
 * Return:
 * - true: The database has been successfully set up.
 * - false: The database is failed to be set up.
 */
static bool
setupDatabase()
{
    HexLogInfo("create the database for keycloak");

    if (isDatabaseSetup()) {
        HexLogInfo("the database for keycloak is already created");
        return true;
    }

    if (!ExecTerraform("apply", "mysql", { "mysql_dbname=" + DB_NAME })) {
        HexLogError("failed to create keycloak database via terraform");
        return false;
    }

    return true;
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

/**
 * Check if Keycloak is deployed or not.
 */
static bool
checkKeycloak()
{
    HexLogInfo("check keycloak");

    if (!K3sWatchRollOut(APP, APP_NAMESPACE, "1s")) {
        HexLogError("failed to see all pods rolled out");
        return false;
    }
    HexLogInfo("all keycloak pods are rolled out");

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
    HexLogInfo("keycloak replica count matched the node count");

    HexLogInfo("checked keycloak");
    return true;
}

/**
 * Deploy Keycloak using Helm.
 */
static bool
updateKeycloak()
{
    HexLogInfo("update keycloak helm chart and roll out pods");

    int nodeCount = K3sGetNodeCounts();
    if (nodeCount < 0) {
        // there is no node to deploy the pods
        nodeCount = 0;
    }

    return HexUtilSystemF(
               0,
               0,
               "/usr/local/bin/helm --kubeconfig=/etc/rancher/k3s/k3s.yaml "
               "upgrade --install %s %s -f %s "
               "-n %s --create-namespace --set replicas=%d",
               CHART_RELEASE_NAME.c_str(),
               KEYCLOAK_CHARTS,
               KEYCLOAK_CHART_VALUES,
               APP_NAMESPACE.c_str(),
               nodeCount)
        == 0;
}

/**
 * Check if the endpoint is available.
 */
static bool
checkKeycloakEndpoint(const std::string& endpointIp)
{
    std::string host = endpointIp;
    host += (":" + std::to_string(K3S_INGRESS_HTTPS_PORT));
    Url url = Url(host, "/auth/realms/master");
    url.scheme = "https";

    // retry 15 times
    bool isSuccessful = false;
    for (int i = 0; i < 15; i++) {
        const HttpResponse r = HttpGet(url);

        if (r.error.length() > 0) {
            HexLogError("failed to send the http request");
        } else {
            if (r.statusCode != 200) {
                HexLogError("keycloak is not ready, status code: %d", r.statusCode);
            } else {
                isSuccessful = true;
            }
        }

        CleanupHttpResponse(r);

        if (isSuccessful) {
            HexLogInfo("keycloak endpoint is ready");
            break;
        } else {
            sleep(1);
        }
    }

    return isSuccessful;
}

/**
 * Check if the Keycloak SAML metadata file exists and is complete.
 */
static bool
hasKeycloakSamlMetadataFile()
{
    if (access(KEYCLOAK_SAML_METADATA_FILE, F_OK) != 0) {
        HexLogError("%s is missing", KEYCLOAK_SAML_METADATA_FILE);
        return false;
    }

    std::uintmax_t samlMetadataFileSize = 0;
    try {
        samlMetadataFileSize = std::filesystem::file_size(KEYCLOAK_SAML_METADATA_FILE);
    } catch (const std::filesystem::filesystem_error& e) {
        HexLogError("failed to get the file size of %s", KEYCLOAK_SAML_METADATA_FILE);
        return false;
    }

    if (samlMetadataFileSize <= 0) {
        HexLogError("%s is not complete", KEYCLOAK_SAML_METADATA_FILE);
        return false;
    }

    return true;
}

/**
 * Download the SAML metadata file from Keycloak,
 * for other SAML service providers to register itself
 * to the SAML IDP, Keycloak.
 */
static bool
downloadKeycloakSamlMetadata(const std::string& endpointIp)
{
    HexLogInfo("download keycloak saml metadata");

    // must use control vip in curl because the content of saml metadata will honor it as ip/hostname
    std::string host = endpointIp;
    host += (":" + std::to_string(K3S_INGRESS_HTTPS_PORT));
    Url url = Url(host, "/auth/realms/master/protocol/saml/descriptor");
    url.scheme = "https";

    // retry 120 times
    bool isDownloadSuccessful = false;
    bool isCopySuccessful = false;
    for (int i = 0; i < 120; i++) {
        const HttpResponse r = HttpGet(url);

        if (r.error.length() > 0) {
            HexLogError("failed to send the http request");
        } else {
            if (r.statusCode != 200) {
                HexLogError("failed to download keycloak saml metadata");
            } else {
                isDownloadSuccessful = true;

                std::string fsError;
                isCopySuccessful = CopyFile(
                    fsError,
                    r.outputFileName,
                    KEYCLOAK_SAML_METADATA_FILE);
            }
        }

        CleanupHttpResponse(r);

        if (isDownloadSuccessful) {
            HexLogInfo("downloaded keycloak saml metadata");
            break;
        } else {
            sleep(1);
        }
    }

    if (isDownloadSuccessful && !isCopySuccessful) {
        HexLogError("failed to persist keycloak saml metadata");
    }

    return isDownloadSuccessful && isCopySuccessful;
}

static bool
Commit(bool modified, int dryLevel)
{
    // TODO: remove this if support dry run
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (!IsControl(s_eCubeRole)) {
        HexLogNotice("keycloak should not be updated from a non-control node");
        return true;
    }

    // set up the database
    if (!isDatabaseSetup()) {
        if (!setupDatabase()) {
            HexLogError("failed to set up the database for keycloak");
        }
    }

    if (s_bApplianceModified) {
        if (!updateKeycloakChartValues(s_loginGreeting)) {
            HexLogError(
                "unable to update %s",
                KEYCLOAK_CHART_VALUES);
            return false;
        }
    }

    if (s_bApplianceModified || !checkKeycloak()) {
        // update keycloak and roll out pods
        HexLogInfo("update keycloak");
        if (!updateKeycloak()) {
            HexLogError("failed to update keycloak");

            // let other modules to commit
            return true;
        }
        HexLogInfo("updated keycloak");

        // check the roll out status of pods
        if (!K3sWatchRollOut(APP, APP_NAMESPACE, "3m")) {
            HexLogError("failed to see all pods rolled out");
        } else {
            HexLogInfo("keycloak pods were all rolled out");
        }

        // check if the Keycloak endpoint is reachable
        if (!checkKeycloakEndpoint("10.32.45.10")) {
            HexLogError("keycloak endpoint is not ready");

            // let other modules to commit
            return true;
        }

        // create default cube groups
        if (!ExecTerraform("apply", "keycloak", {})) {
            HexLogError("failed to create default cube groups via terraform");
        }

        // pull down the saml metadata and save it to /etc/keycloak/saml-metadata.xml
        if (!hasKeycloakSamlMetadataFile()) {
            if (!downloadKeycloakSamlMetadata("10.32.45.10")) {
                HexLogError("failed to download the saml metadata from keycloak");
            }
        }
    }

    return true;
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

static bool
syncSamlMetadata(const std::string myip)
{
    HexLogInfo("sync the keycloak saml metadata file");

    if (!hasKeycloakSamlMetadataFile()) {
        return false;
    }

    // copy the content of the keycloak saml metadata file to a temporary file
    TempFile tmpFile = CreateTempFile();
    if (!tmpFile.isValid) {
        HexLogError("failed to create a temporary file");
        return false;
    }
    std::string fsError;
    if (!CopyFile(fsError, KEYCLOAK_SAML_METADATA_FILE, tmpFile.fileName)) {
        HexLogError("failed to copy the file, error: %s", fsError.c_str());
        return false;
    }

    // sync the file to all control nodes
    HexUtilSystemF(
        0,
        0,
        "hex_sdk cmd -cv scp root@%s:%s %s",
        myip.c_str(),
        tmpFile.fileName.c_str(),
        KEYCLOAK_SAML_METADATA_FILE);

    // clean up the temporary file
    DeleteTempFile(tmpFile);

    HexLogInfo("synced the keycloak saml metadata file");
    return true;
}

static int
ClusterStartMain(int argc, char** argv)
{
    if (argc != 1) {
        return EXIT_FAILURE;
    }

    HexLogInfo("update keycloak");
    if (!updateKeycloak()) {
        HexLogError("failed to update keycloak");
    }
    HexLogInfo("updated keycloak");

    // sync /etc/keycloak/saml-metadata.xml
    std::string myip = G(MGMT_ADDR);
    syncSamlMetadata(myip);

    return EXIT_SUCCESS;
}

CONFIG_TRIGGER_WITH_SETTINGS(keycloak, "cluster_start", ClusterStartMain);

static void
RemoveKeycloakUsage()
{
    fprintf(
        stderr,
        "Usage: %s remove_keycloak [hard]\n"
        "    Option hard is not recoverable on clusters with more than one control node.\n",
        HexLogProgramName());
}

static bool
removeKeycloak(const bool isHard)
{
    if (!IsControl(s_eCubeRole)) {
        HexLogNotice("keycloak should not be removed from a non-control node");
        return true;
    }

    HexLogInfo("remove keycloak");

    if (!ExecTerraform("destroy", "keycloak", {})) {
        HexLogError("failed to remove settings managed by terraform on keycloak");
        return false;
    }
    HexLogInfo("destroyed terraform settings on keycloak");

    if (!ExecHelm("uninstall", CHART_RELEASE_NAME, APP_NAMESPACE)) {
        HexLogError(
            "failed to uninstall helm chart release %s from %s",
            CHART_RELEASE_NAME.c_str(),
            APP_NAMESPACE.c_str());
        return false;
    }
    HexLogInfo("uninstalled keycloak helm chart release");

    if (isHard) {
        if (!ExecTerraform("destroy", "mysql", { "mysql_dbname=" + DB_NAME })) {
            HexLogError("failed to remove keycloak database");
            return false;
        }
        HexLogInfo("destroyed keycloak database via terraform");

        if (!K3sDeleteNamespace(APP_NAMESPACE)) {
            HexLogError("failed to delete namespace %s", APP_NAMESPACE.c_str());
            return false;
        }
        HexLogInfo("deleted keycloak namespace");
    }

    HexLogInfo("removed keycloak");
    return true;
}

static int
RemoveKeycloakMain(int argc, char** argv)
{
    if (argc > 2) {
        return EXIT_FAILURE;
    }

    if (argc == 2) {
        if (std::string(argv[1]).compare("hard") == 0) {
            return removeKeycloak(true) ? EXIT_SUCCESS : EXIT_FAILURE;
        }
    }
    return removeKeycloak(false) ? EXIT_SUCCESS : EXIT_FAILURE;
}

CONFIG_COMMAND_WITH_SETTINGS(remove_keycloak, RemoveKeycloakMain, RemoveKeycloakUsage);

static void
StatusKeycloakUsage()
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
CheckKeycloakUsage()
{
    fprintf(stderr, "Usage: %s check_keycloak\n", HexLogProgramName());
}

static int
CheckKeycloakMain(int argc, char** argv)
{
    return checkKeycloak() ? EXIT_SUCCESS : EXIT_FAILURE;
}

CONFIG_COMMAND(check_keycloak, CheckKeycloakMain, CheckKeycloakUsage);

static void
RepairKeycloakUsage()
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

    HexLogInfo("repair keycloak");

    if (!K3sDeleteAllPods(APP_NAMESPACE)) {
        HexLogError("failed to delete all pods of keycloak");
        return false;
    }
    HexLogInfo("deleted all keycloak pods");

    if (!K3sWatchRollOut(APP, APP_NAMESPACE, "3m")) {
        HexLogError("failed to see all pods rolled out");
        return false;
    }
    HexLogInfo("all keycloak pods are rolled out");

    HexLogInfo("repaired keycloak");
    return true;
}

static int
RepairKeycloakMain(int argc, char** argv)
{
    return repairKeycloak() ? EXIT_SUCCESS : EXIT_FAILURE;
}

CONFIG_COMMAND_WITH_SETTINGS(repair_keycloak, RepairKeycloakMain, RepairKeycloakUsage);

static void
RemoveKeycloakSamlMetadataUsage()
{
    fprintf(stderr, "Usage: %s remove_keycloak_saml_metadata\n", HexLogProgramName());
}

static void
removeKeycloakSamlMetadata()
{
    if (!IsControl(s_eCubeRole)) {
        HexLogNotice("keycloak saml metadata does not exist on a non-control node");
        return;
    }

    HexLogInfo("remove %s", KEYCLOAK_SAML_METADATA_FILE);
    if (access(KEYCLOAK_SAML_METADATA_FILE, F_OK) != 0) {
        HexLogInfo("%s not found", KEYCLOAK_SAML_METADATA_FILE);
        return;
    }

    unlink(KEYCLOAK_SAML_METADATA_FILE);
    HexLogInfo("removed %s", KEYCLOAK_SAML_METADATA_FILE);
}

static int
RemoveKeycloakSamlMetadataMain(int argc, char** argv)
{
    removeKeycloakSamlMetadata();
    return EXIT_SUCCESS;
}

CONFIG_COMMAND_WITH_SETTINGS(remove_keycloak_saml_metadata, RemoveKeycloakSamlMetadataMain, RemoveKeycloakSamlMetadataUsage);
