// CUBE SDK

#include "cli_iaas_volume.hpp"

// This mode is not available in STRICT error state
CLI_MODE(
    CLI_TOP_COMMAND_IAAS,
    CLI_COMMAND_IAAS_VOLUME,
    "Work with the IaaS volume settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

static int
ResetMain(int argc, const char** argv)
{
    /*
     * [0]="reset", [1]=<volume id>
     */
    if (argc > 2)
        return CLI_INVALID_ARGS;

    std::string uuid;
    int index;

    std::string optCmd = std::string(HEX_SDK) + " os_cinder_volume_list";
    std::string descCmd = std::string(HEX_SDK) + " -v os_cinder_volume_list";

    if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &uuid, "Select a volume to be reset: ") != CLI_SUCCESS) {
        CliPrintf("instance name is missing or not found");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    HexSpawn(0, HEX_SDK, "os_cinder_volume_reset", uuid.c_str(), NULL);

    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_VOLUME,
    "reset",
    ResetMain,
    NULL,
    "Reset volume state to available for attaching.",
    "reset [<volume id>]");

static int
QuotaSetMain(int argc, const char** argv)
{
    if (argc > 5 /* [0]="quota_set" [1]="domain" [2]="tenant" [3]="type" [4]="quota" */)
        return CLI_INVALID_ARGS;

    int index;
    std::string domain, tenant, type, quota;
    std::string cmd;

    cmd = std::string(HEX_SDK) + " os_list_domain_basic";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    cmd = std::string(HEX_SDK) + " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &tenant, "Select tenant: ") != CLI_SUCCESS) {
        CliPrintf("Invalid tenant");
        return CLI_INVALID_ARGS;
    }

    cmd = std::string(HEX_SDK) + " os_cinder_quota_list";
    if (CliMatchCmdHelper(argc, argv, 3, cmd, &index, &type, "Select type: ") != CLI_SUCCESS) {
        CliPrintf("Invalid quota type");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 4, "Input quota value: ", &quota) || quota.length() <= 0) {
        CliPrint("quota value is required");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_cinder_quota_update", tenant.c_str(), type.c_str(), quota.c_str(), NULL);

    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_VOLUME,
    "quota_set",
    QuotaSetMain,
    NULL,
    "Set volume quota for a tenant.",
    "quota_set [<domain>] [<tenant>] [<type>] [<quota>]");

static int
QuotaShowMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="quota_show" [1]="domain" [2]="tenant" */)
        return CLI_INVALID_ARGS;

    int index;
    std::string domain, tenant;
    std::string cmd;

    cmd = std::string(HEX_SDK) + " os_list_domain_basic";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    cmd = std::string(HEX_SDK) + " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &tenant, "Select tenant: ") != CLI_SUCCESS) {
        CliPrintf("Invalid tenant");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_cinder_quota_show", tenant.c_str(), NULL);

    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_VOLUME,
    "quota_show",
    QuotaShowMain,
    NULL,
    "Show volume quota for a tenant.",
    "quota_show [<domain>] [<tenant>]");

/**
 * Get names of NFS storage backends.
 * The backends must be configured, enabled, and up.
 *
 * @return names of NFS storage backends
 */
static const std::vector<std::string>
getNfsStorageBackends()
{
    std::vector<std::string> result;

    HexPolicyManager policyManager;
    ExtStoragePolicy policy;
    if (!policyManager.load(policy)) {
        return result;
    }

    const ExtStorageConfig config = policy.getConfig();
    std::vector<std::string> configuredBackends;
    for (const std::string& b : config.storageBackends) {
        const std::vector<IniSection> backendConfig = GetConfiguredBackendDetails(b);

        for (const IniSection& section : backendConfig) {
            // we only need the main section
            if (section.header != b) {
                continue;
            }

            // we only need the NFS storage backends
            std::map<std::string, std::string>::const_iterator driverSetting = section.settings.find("volume_driver");
            if (driverSetting != section.settings.end() && driverSetting->second == CINDER_VOLUME_DRIVER_NFS) {
                configuredBackends.push_back(b);
            }
        }
    }

    const std::vector<ExistingBackend> existingBackends = GetExistingBackends();
    for (const std::string& cb : configuredBackends) {
        for (const ExistingBackend& eb : existingBackends) {
            if ((cb + "@" + cb) != eb.host) {
                continue;
            }

            // the backend should be enabled and up
            if (eb.status == "enabled" && eb.state == "up") {
                result.push_back(cb);
            } else {
                break;
            }
        }
    }

    return result;
}

/**
 * Find the mount point on the file system from the NFS host export.
 *
 * @param nfsExport export path of the NFS share
 * @return mount point
 */
static const std::string
findNfsMountPointFromExport(const std::string& nfsExport)
{
    // open the system mount file
    std::ifstream mountsFile("/proc/mounts");
    if (!mountsFile.is_open()) {
        HexLogError("failed to open /proc/mounts");
        return "";
    }

    std::string line;
    // read the file line by line
    while (std::getline(mountsFile, line)) {
        std::stringstream ss(line);
        std::string device;
        std::string mountPoint;
        std::string fsType;

        // extract the first three fields from the line
        if (ss >> device >> mountPoint >> fsType) {
            // check if the filesystem is NFS and the export matches
            if (fsType.find("nfs") != std::string::npos && device == nfsExport) {
                return mountPoint;
            }
        }
    }

    // key not found
    return "";
}

struct mountPoint {
    std::string exportPath;
    std::string target;
};

/**
 * Get NFS mount point infos of an NFS storage backend.
 *
 * @param name NFS storage backend name
 * @return mount point infos of the NFS storage backend
 */
static const std::vector<mountPoint>
getNfsMountPoints(const std::string name)
{
    // get the file path to nfs share config
    const std::string nfsBackendConfigFilePath = std::string("/etc/cinder/cinder.d") + "/ext_storage_" + name + ".conf";
    std::string fsError;
    const std::string backendConfig = ReadFile(fsError, nfsBackendConfigFilePath);
    if (!fsError.empty()) {
        HexLogError(
            "failed to read the backend config file of %s, %s",
            name.c_str(),
            fsError.c_str());
        return {};
    }

    const std::vector<IniSection> nfsBackendConfig = ParseIni(backendConfig);
    std::string nfsShareFilePath;
    for (const IniSection& s : nfsBackendConfig) {
        if (s.header != name) {
            continue;
        }

        std::map<std::string, std::string>::const_iterator c = s.settings.find("nfs_shares_config");
        if (c != s.settings.end()) {
            nfsShareFilePath = c->second;
            break;
        }
    }

    // read the nfs share config
    if (nfsShareFilePath.empty()) {
        return {};
    }

    const std::string nfsShareFile = ReadFile(fsError, nfsShareFilePath);
    if (!fsError.empty()) {
        HexLogError(
            "failed to read the nfs share config file %s, %s",
            nfsShareFilePath.c_str(),
            fsError.c_str());
        return {};
    }

    // get the export of the mount points
    std::stringstream ss(nfsShareFile);
    std::string line;
    std::vector<std::string> exportDirectories;
    while (std::getline(ss, line)) {
        const std::string trimmedLine = Trim(line);

        if (trimmedLine.empty()) {
            continue;
        }

        exportDirectories.push_back(trimmedLine);
    }

    // get the target of the mount points
    std::vector<mountPoint> mountPoints;
    for (const std::string& e : exportDirectories) {
        const std::string d = findNfsMountPointFromExport(e);
        if (d.empty()) {
            continue;
        }

        mountPoints.push_back({
            .exportPath = e,
            .target = d,
        });
    }

    return mountPoints;
}

/**
 * Check if the file is already managed by Cinder.
 *
 * @param filePath full path of the file
 * @param volumeType
 * @return true or false
 */
static bool
isFileAlreadyManagedByCinder(
    const std::string& filePath,
    const std::string& volumeType)
{
    const std::filesystem::path p(filePath);
    const std::string basename = p.filename().string();
    if (basename.empty()) {
        return false;
    }

    // check if the file name starts with "volume-"
    const std::string managedVolumeNamePrefix = "volume-";
    std::string volumeId;
    if (basename.rfind(managedVolumeNamePrefix, 0) == 0) {
        volumeId = basename.substr(managedVolumeNamePrefix.length());
    }
    if (volumeId.empty()) {
        return false;
    }

    // check with OpenStack
    const ExecSyncResult r = OpenstackExec("volume show " + volumeId + " -f json");
    if (r.exitCode != 0) {
        return false;
    }

    // parse the output
    std::string jsonError;
    const json11::Json volumeDetail = json11::Json::parse(r.stdoutOutput, jsonError);
    if (!jsonError.empty()) {
        return false;
    }
    if (!volumeDetail["type"].is_string()) {
        return false;
    }
    if (volumeDetail["type"].string_value() != volumeType) {
        return false;
    }

    return true;
}

struct fileInfo : public mountPoint {
    std::string filePath;
};

static int
MigrateLargeVolumeFromNfsMain(int argc, const char** argv)
{
    /**
     * [0]="migrate_large_volume_from_nfs"
     * [1]=<source_nfs_storage_backend>
     * [2]=<file_name>
     * [3]=<volume_name>
     * [4]=<domain>
     * [5]=<project>
     * [6]=<destination_volume_type>
     */
    if (argc > 7) {
        return CLI_INVALID_ARGS;
    }

    std::string cmd = "";
    int index;

    std::string sourceNfsStorageBackend;
    std::string filePath;
    fileInfo fileExtraInfo;
    std::string volumeName;
    std::string domain;
    std::string project;
    std::string destinationVolumeType;

    if (CliMatchListHelper(
            argc,
            argv,
            1,
            getNfsStorageBackends(),
            &index,
            &sourceNfsStorageBackend,
            "Select the source NFS storage backend: ")
        != CLI_SUCCESS) {
        CliPrintf("Invalid source NFS storage backend");
        return CLI_INVALID_ARGS;
    }

    const std::vector<mountPoint> nfsMountPoints = getNfsMountPoints(sourceNfsStorageBackend);
    std::vector<fileInfo> fileInfos;
    CliList files;
    for (const mountPoint& p : nfsMountPoints) {
        std::string fsError;
        const CliList fl = GetFilesUnderDirectory(fsError, p.target);
        if (!fsError.empty()) {
            HexLogError("%s", fsError.c_str());
        }

        for (const std::string& f : fl) {
            /**
             * We would skip volumes already managed by Cinder.
             * Since we enforced host name = volume backend name
             * = volume backend pool name = type name, we would use
             * the backend name as the volume type.
             */
            if (isFileAlreadyManagedByCinder(f, sourceNfsStorageBackend)) {
                continue;
            }

            fileInfo fi;
            fi.exportPath = p.exportPath;
            fi.target = p.target;
            fi.filePath = f;
            fileInfos.push_back(fi);

            // get the relative path of the file on the NFS share
            std::string relativeFilePath = f;
            if (relativeFilePath.rfind(p.target, 0) == 0) {
                relativeFilePath.erase(0, p.target.length());
            }

            files.push_back(p.exportPath + relativeFilePath);
        }
    }

    if (CliMatchListHelper(
            argc,
            argv,
            2,
            files,
            &index,
            &filePath,
            "Select the file path: ")
        != CLI_SUCCESS) {
        CliPrintf("Invalid file path");
        return CLI_INVALID_ARGS;
    }
    if (index >= 0 && (std::size_t)index < fileInfos.size()) {
        fileExtraInfo = fileInfos[index];
    }

    cmd = HEX_SDK " os_list_domain_basic | awk '{print tolower($0)}'";
    if (CliMatchCmdHelper(argc, argv, 4, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 5, cmd, &index, &project, "Select project: ") != CLI_SUCCESS) {
        CliPrintf("Invalid project");
        return CLI_INVALID_ARGS;
    }

    std::cout << "backend: " << sourceNfsStorageBackend << std::endl;
    std::cout << "filePath: " << filePath << std::endl;
    std::cout << "fileInfo export: " << fileExtraInfo.exportPath << std::endl;
    std::cout << "fileInfo target: " << fileExtraInfo.target << std::endl;
    std::cout << "fileInfo path: " << fileExtraInfo.filePath << std::endl;
    std::cout << "domain: " << domain << std::endl;
    std::cout << "project: " << project << std::endl;
    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_VOLUME,
    "migrate_large_volume_from_nfs",
    MigrateLargeVolumeFromNfsMain,
    NULL,
    "Migrate a large volume from a configured NFS volume backend.",
    "migrate_large_volume_from_nfs <source_nfs_storage_backend> "
    "<file_path> <volume_name> <domain> <project> <destination_volume_type>");
