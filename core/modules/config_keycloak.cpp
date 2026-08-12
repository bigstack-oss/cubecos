// CUBE SDK

#include "config_keycloak.hpp"

static const std::string APP = "statefulset.apps/keycloak-keycloakx";
static const std::string APP_NAMESPACE = "keycloak";
static const std::string CHART_RELEASE_NAME = "keycloak";
static const char KEYCLOAK_CHARTS[] = "/opt/keycloak/keycloakx-*.tgz";
static const char KEYCLOAK_CHART_VALUES[] = "/opt/keycloak/chart-values.yaml";
static const std::string DB_NAME = "keycloak";
static const char KEYCLOAK_SAML_METADATA_FILE[] = "/etc/keycloak/saml-metadata.xml";
static const std::string KEYCLOAK_ADMIN_PASSWORD_K8S_SECRET = "admin-password";
static const std::string KEYCLOAK_ADMIN_PASSWORD_TERRAFORM_VARIABLE_FILE
    = "/etc/cube/cos/terraform/values/keycloak-admin-password.tfvars";
static const int SAML_METADATA_STUCK_NOTIFY_SECS = 600;
// operator escape hatch: touching this releases the saml metadata gate below
// (one-shot; consumed when honored). /run is tmpfs so it cannot outlive a boot.
static const char SAML_METADATA_GATE_RELEASE[] = "/run/cube_keycloak_saml_gate_release";

// external global variables
CONFIG_GLOBAL_STR_REF(MGMT_ADDR);
CONFIG_GLOBAL_STR_REF(SHARED_ID);

// using external tunings
CONFIG_TUNING_SPEC_STR(APPLIANCE_LOGIN_GREETING);
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_HOSTS);

// parse tunings
PARSE_TUNING_STR(s_loginGreeting, APPLIANCE_LOGIN_GREETING);
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);
PARSE_TUNING_X_STR(s_ctrlHosts, CUBESYS_CONTROL_HOSTS, 1);

static bool s_bApplianceModified = false;
static bool s_bNetModified = false;
static bool s_bCubeModified = false;

static ConfigString s_hostname;
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
ParseNet(const char* name, const char* value, bool isNew)
{
    if (strcmp(name, NET_HOSTNAME) == 0) {
        s_hostname.parse(value, isNew);
    }

    return true;
}

static void
NotifyNet(bool modified)
{
    s_bNetModified = s_hostname.modified();
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

    if (!ExecTerraform("apply", "mysql", { "mysql_dbname=" + DB_NAME }, {})) {
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
 * Create needed DB secrets for Keycloak.
 */
static bool
createKeycloakDbSecrets()
{
    const std::string secretName = "keycloak-db-secret";
    // check if the secret exists
    const ExecSyncResult cr = ExecBashSync(
        0,
        false,
        false,
        {},
        "/usr/local/bin/k3s kubectl get secret " + secretName
            + " -n " + APP_NAMESPACE);
    if (cr.exitCode == 0) {
        return true;
    }

    // create the secret
    const ExecSyncResult r = ExecBashSync(
        0,
        false,
        false,
        {},
        "/usr/local/bin/k3s kubectl create secret generic " + secretName
            + " --from-file=/opt/keycloak/db"
            + " -n " + APP_NAMESPACE);
    return (r.exitCode == 0);
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
 * Check if it is possible to update Keycloak. This would iron out some edge cases.
 */
static bool
isUpdateKeycloakPossible(
    const bool isHa,
    const std::string& hostname,
    const std::string& controlNodes)
{
    if (!isHa) {
        // always possible to update Keycloak on non-HA nodes
        return true;
    }

    if (IsRollingUpgrade() && !IsLastControlNode(hostname, controlNodes)) {
        HexLogInfo("skipped updating keycloak, reason: rolling upgrade");
        return false;
    }

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
    if (nodeCount == 0) {
        /**
         * Deploying Keycloak to 0 node is meaningless.
         * However, sometimes, during bootstrapping, K3S would report itself having 0 node.
         * We would force this to at least one instead.
         */
        nodeCount = 1;
    }

    /**
     * chart-values.yaml needs the address Keycloak is reached on so it can pin the admin
     * console URL, which Keycloak resolves separately from the frontend one.
     */
    const std::string sharedId = G(SHARED_ID);

    const std::string cmd = std::string()
        + "/usr/local/bin/helm --kubeconfig=/etc/rancher/k3s/k3s.yaml "
        + "upgrade --install " + CHART_RELEASE_NAME + " " + KEYCLOAK_CHARTS + " "
        + "-f " + KEYCLOAK_CHART_VALUES + " "
        + "-n " + APP_NAMESPACE + " "
        + "--create-namespace "
        + "--set replicas=" + std::to_string(nodeCount) + " "
        + "--set cubeController=" + sharedId;

    // parallel control-node applies race on the same helm release; retry the
    // transient "another operation in progress" lock
    for (int attempt = 0; attempt < 6; attempt++) {
        const ExecSyncResult r = ExecBashSync(0, false, false, {}, cmd);
        if (r.exitCode == 0)
            return true;
        HexLogWarning("keycloak helm upgrade failed (attempt %d/6); retrying", attempt + 1);
        sleep(15);
    }
    return false;
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
        const HttpRequest req = {
            .url = url,
            .connectTimeoutSecs = 10,
            .maxTimeSecs = 60,
        };
        const HttpResponse res = GetHttp(req);

        if (res.error.length() > 0) {
            HexLogError("failed to send the http request");
        } else {
            if (!isHttpResponseSuccessful(res)) {
                HexLogError("keycloak is not ready, status code: %d", res.statusCode);
            } else {
                isSuccessful = true;
            }
        }

        CleanupHttpResponse(res);

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

    // single time-bounded attempt: the commit gate loop owns the retry policy
    // and must regain control quickly enough to notify the console on schedule
    bool isDownloadSuccessful = false;
    bool isCopySuccessful = false;
    const HttpRequest req = {
        .url = url,
        .connectTimeoutSecs = 10,
        .maxTimeSecs = 60,
    };
    const HttpResponse res = GetHttp(req);

    if (res.error.length() > 0) {
        HexLogError("failed to send the http request");
    } else {
        if (!isHttpResponseSuccessful(res)) {
            HexLogError("failed to download keycloak saml metadata");
        } else {
            isDownloadSuccessful = true;

            std::string fsError;
            isCopySuccessful = CopyFile(
                fsError,
                res.outputFileName,
                KEYCLOAK_SAML_METADATA_FILE);
        }
    }

    CleanupHttpResponse(res);

    if (isDownloadSuccessful && !isCopySuccessful) {
        HexLogError("failed to persist keycloak saml metadata");
    }

    if (isDownloadSuccessful && isCopySuccessful) {
        HexLogInfo("downloaded keycloak saml metadata");
        return true;
    }
    return false;
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

    // check if K3S is running, if not, the actions below are not executable
    if (!IsK3sReady()) {
        // let other modules to commit
        return true;
    }

    // set up the namespace if not set
    if (!K3sHasNamespace(APP_NAMESPACE)) {
        if (!K3sCreateNamespace(APP_NAMESPACE)) {
            HexLogError("failed to create the namespace for keycloak");

            // let other modules to commit
            return true;
        }
    }

    // create db secrets on k3s
    if (!createKeycloakDbSecrets()) {
        HexLogError("failed to create the db secrets for keycloak");

        // let other modules to commit
        return true;
    }

    bool isKeycloakUpdated = false;
    if ((s_bApplianceModified || !checkKeycloak())
        && isUpdateKeycloakPossible(s_ha, s_hostname, s_ctrlHosts)) {
        // scale keycloak to one pod per control host + roll out
        HexLogInfo("update keycloak");
        if (updateKeycloak()) {
            HexLogInfo("updated keycloak");
            isKeycloakUpdated = true;

            // check the roll out status of pods
            if (!K3sWatchRollOut(APP, APP_NAMESPACE, "3m")) {
                HexLogError("failed to see all pods rolled out");
            } else {
                HexLogInfo("keycloak pods were all rolled out");
            }
        } else {
            // a lost scale-up race is self-healing (the winner sets replicas);
            // don't early-return, or we'd skip the metadata gate below
            HexLogError("failed to update keycloak (scale race?); continuing to saml metadata gate");
        }
    }

    // always gate on the SAML metadata file (SSO reads it): the commit must not
    // report success without it. Needs only keycloak reachable, not this node's
    // own upgrade. Retry until present, or the operator releases the gate.
    std::string sharedId = G(SHARED_ID);
    time_t lastNotify = time(NULL);
    while (!hasKeycloakSamlMetadataFile()) {
        if (downloadKeycloakSamlMetadata(sharedId))
            break;
        HexLogError("failed to download the saml metadata from keycloak");

        if (access(SAML_METADATA_GATE_RELEASE, F_OK) == 0) {
            unlink(SAML_METADATA_GATE_RELEASE);
            HexLogWarning("saml metadata gate released by operator via %s;"
                          " proceeding without %s (SSO will be degraded)",
                          SAML_METADATA_GATE_RELEASE, KEYCLOAK_SAML_METADATA_FILE);
            break;
        }

        if (time(NULL) - lastNotify >= SAML_METADATA_STUCK_NOTIFY_SECS) {
            HexLogWarning("keycloak saml metadata download is stuck; notified the console");
            HexSystemF(0,
                "echo 'CUBE: setup is waiting for the keycloak SAML metadata"
                " (https://%s:%d/auth/realms/master/protocol/saml/descriptor)"
                " and cannot proceed until it is downloaded."
                " Check keycloak and k3s."
                " To skip and continue with degraded SSO, run: touch %s' > /dev/console",
                sharedId.c_str(), K3S_INGRESS_HTTPS_PORT, SAML_METADATA_GATE_RELEASE);
            lastNotify = time(NULL);
        }

        sleep(10);
    }

    // create default cube groups (owned by the node that scaled keycloak),
    // gated on the endpoint being reachable. Idempotent.
    if (isKeycloakUpdated && checkKeycloakEndpoint(sharedId)) {
        if (!ExecTerraform(
                "apply",
                "keycloak",
                { "cube_controller=" + sharedId },
                { KEYCLOAK_ADMIN_PASSWORD_TERRAFORM_VARIABLE_FILE })) {
            HexLogError("failed to create default cube groups via terraform");
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
CONFIG_OBSERVES(keycloak, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(keycloak, cubesys, ParseCube, NotifyCube);

CONFIG_MIGRATE(keycloak, "/etc/keycloak");
CONFIG_MIGRATE(keycloak, "/etc/cube/cos/terraform");

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
        HEX_SDK " cmd -cv scp root@%s:%s %s",
        myip.c_str(),
        tmpFile.fileName.c_str(),
        KEYCLOAK_SAML_METADATA_FILE);
    HexUtilSystemF(
        0,
        0,
        HEX_SDK " cmd chmod 664 %s",
        KEYCLOAK_SAML_METADATA_FILE);
    HexUtilSystemF(
        0,
        0,
        HEX_SDK " cmd chown root:admin %s",
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

    if (!isUpdateKeycloakPossible(s_ha, s_hostname, s_ctrlHosts)) {
        return EXIT_SUCCESS;
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
InstallKeycloakUsage()
{
    fprintf(stderr, "Usage: %s install_keycloak\n", HexLogProgramName());
}

static int
InstallKeycloakMain(int argc, char** argv)
{
    return Commit(false, DRYLEVEL_NONE) ? EXIT_SUCCESS : EXIT_FAILURE;
}

CONFIG_COMMAND_WITH_SETTINGS(install_keycloak, InstallKeycloakMain, InstallKeycloakUsage);

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

    std::string sharedId = G(SHARED_ID);
    if (!ExecTerraform(
            "destroy",
            "keycloak",
            { "cube_controller=" + sharedId },
            { KEYCLOAK_ADMIN_PASSWORD_TERRAFORM_VARIABLE_FILE })) {
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
        if (!ExecTerraform("destroy", "mysql", { "mysql_dbname=" + DB_NAME }, {})) {
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

    HexLogInfo("update keycloak");
    if (!updateKeycloak()) {
        HexLogError("failed to update keycloak");
        return false;
    }
    HexLogInfo("updated keycloak");

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

/**
 * Check if the admin password is stored in K8S secret on K3S.
 */
static bool
isKeycloakUserPasswordInK8sSecret()
{
    bool ret = HexUtilSystemF(
                   0,
                   0,
                   "/usr/local/bin/k3s kubectl get secret %s -n %s",
                   KEYCLOAK_ADMIN_PASSWORD_K8S_SECRET.c_str(),
                   APP_NAMESPACE.c_str())
        == 0;

    if (ret) {
        HexLogInfo("found the existing keycloak admin password");
    }

    return ret;
}

/**
 * Get the admin password from the K8S secret.
 */
static std::string
getKeycloakAdminPasswordFromK8sSecret()
{
    if (!isKeycloakUserPasswordInK8sSecret()) {
        return "";
    }

    TempFile base64encodedAdminPass = CreateTempFile();
    if (!base64encodedAdminPass.isValid) {
        HexLogError("failed to create a temporary file");
        return "";
    }
    if (HexUtilSystemF(
            0,
            0,
            "/usr/local/bin/k3s kubectl get secret %s -n %s -o jsonpath='{.data.password}' > %s",
            KEYCLOAK_ADMIN_PASSWORD_K8S_SECRET.c_str(),
            APP_NAMESPACE.c_str(),
            base64encodedAdminPass.fileName.c_str())
        != 0) {
        HexLogError("failed to read the existing keycloak admin password k8s secret");
        return "";
    }
    HexLogInfo("extracted the existing keycloak admin password");

    const std::string base64encodedAdminPassString = HexUtilPOpen(
        "base64 --decode %s",
        base64encodedAdminPass.fileName.c_str());
    DeleteTempFile(base64encodedAdminPass);

    return base64encodedAdminPassString;
}

/**
 * Save the new admin password to the K8S secret.
 */
static bool
saveKeycloakUserPasswordToK8sSecret(
    const bool& hasOldOne,
    const std::string& password)
{
    if (hasOldOne) {
        if (HexUtilSystemF(
                0,
                0,
                "/usr/local/bin/k3s kubectl delete secret %s -n %s",
                KEYCLOAK_ADMIN_PASSWORD_K8S_SECRET.c_str(),
                APP_NAMESPACE.c_str())
            != 0) {
            HexLogError("failed to delete the old keycloak admin password k8s secret");
            return false;
        }
    }

    if (HexUtilSystemF(
            0,
            0,
            "/usr/local/bin/k3s kubectl create secret generic %s --from-literal=password='%s' -n %s",
            KEYCLOAK_ADMIN_PASSWORD_K8S_SECRET.c_str(),
            password.c_str(),
            APP_NAMESPACE.c_str())
        != 0) {
        HexLogError("failed to save keycloak admin password as a k8s secret");
        return false;
    }

    return true;
}

static void
GetKeycloakAdminPasswordUsage()
{
    fprintf(stderr, "Usage: %s get_keycloak_admin_password\n", HexLogProgramName());
}

static int
GetKeycloakAdminPasswordMain(int argc, char** argv)
{
    std::string adminPassInK8sSecret = getKeycloakAdminPasswordFromK8sSecret();
    if (adminPassInK8sSecret.empty()) {
        std::cout << "admin";
        return EXIT_SUCCESS;
    }

    std::cout << adminPassInK8sSecret;
    return EXIT_SUCCESS;
}

CONFIG_COMMAND(get_keycloak_admin_password, GetKeycloakAdminPasswordMain, GetKeycloakAdminPasswordUsage);

static void
UpdateKeycloakAdminPasswordUsage()
{
    fprintf(stderr, "Usage: %s update_keycloak_admin_password <password>\n", HexLogProgramName());
}

static std::string
getKeycloakAdminAccessToken(
    const std::string& endpointIp,
    const std::string& adminPass)
{
    HexLogInfo("get keycloak admin access token");

    std::string host = endpointIp;
    host += (":" + std::to_string(K3S_INGRESS_HTTPS_PORT));
    Url url = Url(host, "/auth/realms/master/protocol/openid-connect/token");
    url.scheme = "https";

    const std::vector<std::string> formBody = {
        "grant_type=password",
        "client_id=admin-cli",
        "username=admin",
        "password=" + adminPass,
    };

    const HttpResponse r = PostFormHttp(url, formBody);

    if (!r.error.empty()) {
        HexLogError("failed to send the http request");

        CleanupHttpResponse(r);
        return "";
    }
    if (!isHttpResponseSuccessful(r)) {
        HexLogError("failed to get the response");

        CleanupHttpResponse(r);
        return "";
    }

    std::string fsError;
    const std::string responseString = ReadFile(fsError, r.outputFileName);
    CleanupHttpResponse(r);

    if (!fsError.empty()) {
        HexLogError("failed to read out the response");
        return "";
    }

    std::string jsonError;
    const json11::Json responseJson = json11::Json::parse(responseString.c_str(), jsonError);
    if (!jsonError.empty()) {
        HexLogError("failed to parse the response");
        return "";
    }

    std::string token;
    if (responseJson["access_token"].is_string()) {
        token = responseJson["access_token"].string_value();
    }

    HexLogInfo("got keycloak admin access token");
    return token;
}

static std::string
getKeycloakUserId(
    const std::string& endpointIp,
    const std::string& accessToken,
    const std::string& username)
{
    HexLogInfo("get keycloak user id of user %s", username.c_str());

    std::string host = endpointIp;
    host += (":" + std::to_string(K3S_INGRESS_HTTPS_PORT));
    Url url = Url(
        host,
        "/auth/admin/realms/master/users",
        {
            { "username", username },
        });
    url.scheme = "https";

    const HttpRequest req = {
        .url = url,
        .header = {
            { "Authorization", "Bearer " + accessToken },
        },
    };
    const HttpResponse res = GetHttp(req);

    if (!res.error.empty()) {
        HexLogError("failed to send the http request");

        CleanupHttpResponse(res);
        return "";
    }
    if (!isHttpResponseSuccessful(res)) {
        HexLogError("failed to get the response");

        CleanupHttpResponse(res);
        return "";
    }

    std::string fsError;
    const std::string responseString = ReadFile(fsError, res.outputFileName);
    CleanupHttpResponse(res);

    if (!fsError.empty()) {
        HexLogError("failed to read out the response");
        return "";
    }

    std::string jsonError;
    const json11::Json responseJson = json11::Json::parse(responseString.c_str(), jsonError);
    if (!jsonError.empty()) {
        HexLogError("failed to parse the response");
        return "";
    }

    std::string userId;
    if (responseJson.is_array()) {
        const json11::Json::array& userArray = responseJson.array_items();

        if (userArray.size() > 0 && userArray[0]["id"].is_string()) {
            userId = userArray[0]["id"].string_value();
        }
    }

    HexLogInfo("got keycloak user id of user %s", username.c_str());
    return userId;
}

static bool
updateKeycloakUserPassword(
    const std::string& endpointIp,
    const std::string& accessToken,
    const std::string& userId,
    const std::string& password)
{
    HexLogInfo("update the password of the keycloak user with user id %s", userId.c_str());

    std::string host = endpointIp;
    host += (":" + std::to_string(K3S_INGRESS_HTTPS_PORT));
    Url url = Url(
        host,
        "/auth/admin/realms/master/users/" + userId + "/reset-password");
    url.scheme = "https";

    const HttpRequest req = {
        .method = "PUT",
        .url = url,
        .header = {
            { "Authorization", "Bearer " + accessToken },
            { "Content-Type", "application/json" },
        },
        .body = R"({"type":"password","value":")" + password + R"(","temporary":false})",
    };
    const HttpResponse res = DoHttp(req);

    if (!res.error.empty()) {
        HexLogError("failed to send the http request");

        CleanupHttpResponse(res);
        return false;
    }
    if (!isHttpResponseSuccessful(res)) {
        HexLogError("failed to get the response");

        CleanupHttpResponse(res);
        return false;
    }
    CleanupHttpResponse(res);

    HexLogInfo("updated the password of the keycloak user with user id %s", userId.c_str());
    return true;
}

/**
 * Save the new admin password to Terraform variable file.
 */
static bool
saveKeycloakAdminPasswordToTerraformVariableFile(const std::string& password)
{
    const std::vector<std::string> fileContent = {
        "keycloak_admin_password = \"" + password + "\"\n",
    };

    std::string fsError;
    if (!WriteFile(
            fsError,
            KEYCLOAK_ADMIN_PASSWORD_TERRAFORM_VARIABLE_FILE,
            fileContent)) {
        HexLogError("%s", fsError.c_str());
        return false;
    }

    return true;
}

static bool
updateKeycloakAdminPassword(
    const std::string& endpointIp,
    const std::string& password)
{
    /**
     * Retrieve the existing password,
     * use the default one if not stored in K8S secret.
     */
    bool isAdminPassStored = isKeycloakUserPasswordInK8sSecret();
    std::string adminPass = "admin";
    if (isAdminPassStored) {
        const std::string adminPassInK8sSecret = getKeycloakAdminPasswordFromK8sSecret();
        if (adminPassInK8sSecret.empty()) {
            HexLogError("failed to get the admin password from the k8s secret");
            return false;
        }

        adminPass = adminPassInK8sSecret;
    }

    // get the admin access token
    const std::string token = getKeycloakAdminAccessToken(endpointIp, adminPass);
    if (token.empty()) {
        HexLogError("failed to get the keycloak admin access token");
        return false;
    }

    // get the user id of user admin
    const std::string userId = getKeycloakUserId(endpointIp, token, "admin");
    if (userId.empty()) {
        HexLogError("failed to get the user id");
        return false;
    }

    // set the new password
    if (!updateKeycloakUserPassword(endpointIp, token, userId, password)) {
        HexLogError("failed to update the password of the keycloak user");
        return false;
    }

    // save the new password to the k8s secret
    if (!saveKeycloakUserPasswordToK8sSecret(isAdminPassStored, password)) {
        HexLogError("failed to save keycloak admin password to the k8s secret");
        return false;
    }

    // update the password used in terraform provider
    if (!saveKeycloakAdminPasswordToTerraformVariableFile(password)) {
        HexLogError("failed to update keycloak admin password to the terraform variable file");
        return false;
    }

    return true;
}

static int
UpdateKeycloakAdminPasswordMain(int argc, char** argv)
{
    if (argc != 2) {
        return EXIT_FAILURE;
    }

    const std::string password = argv[1];
    if (password.empty()) {
        return EXIT_FAILURE;
    }

    std::string sharedId = G(SHARED_ID);
    return updateKeycloakAdminPassword(sharedId, password) ? EXIT_SUCCESS : EXIT_FAILURE;
}

CONFIG_COMMAND_WITH_SETTINGS(update_keycloak_admin_password, UpdateKeycloakAdminPasswordMain, UpdateKeycloakAdminPasswordUsage);

/**
 * Check if we could use the stored Keycloak admin password to log in Keycloak.
 */
static bool
checkKeycloakAdminPassword(const std::string& endpointIp)
{
    std::string currentAdminPass;
    if (isKeycloakUserPasswordInK8sSecret()) {
        currentAdminPass = getKeycloakAdminPasswordFromK8sSecret();
    } else {
        currentAdminPass = "admin";
    }

    const std::string token = getKeycloakAdminAccessToken(endpointIp, currentAdminPass);

    if (token.empty()) {
        HexLogError("failed to log in keycloak using the current admin password");
        return false;
    }

    return true;
}

static void
CheckKeycloakAdminPasswordUsage()
{
    fprintf(stderr, "Usage: %s check_keycloak_admin_password <password>\n", HexLogProgramName());
}

static int
CheckKeycloakAdminPasswordMain(int argc, char** argv)
{
    std::string sharedId = G(SHARED_ID);
    return checkKeycloakAdminPassword(sharedId) ? EXIT_SUCCESS : EXIT_FAILURE;
}

CONFIG_COMMAND_WITH_SETTINGS(check_keycloak_admin_password, CheckKeycloakAdminPasswordMain, CheckKeycloakAdminPasswordUsage);
