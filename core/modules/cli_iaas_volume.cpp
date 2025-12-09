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
 * Get the volume type by ID.
 *
 * @param volumeId
 * @return volume type
 */
static const std::string
getVolumeTypeById(const std::string& volumeId)
{
    const ExecSyncResult r = OpenstackExec("volume show \"" + volumeId + "\" -f json");
    if (r.exitCode != 0) {
        HexLogError("%s", r.stderrOutput.c_str());
        return "";
    }

    // parse the output
    std::string jsonError;
    const json11::Json volumeDetail = json11::Json::parse(r.stdoutOutput, jsonError);
    if (!jsonError.empty()) {
        HexLogError("%s", jsonError.c_str());
        return "";
    }
    if (!volumeDetail["type"].is_string()) {
        return "";
    }

    return volumeDetail["type"].string_value();
}

/**
 * Check if the file is already managed by Cinder.
 *
 * @param filePath full path of the file
 * @param volumeType
 * @return true or false
 */
static const bool
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
    return (getVolumeTypeById(volumeId) == volumeType);
}

/**
 * Check if the volume is already in raw format.
 *
 * @param filePath the local full path of the file
 * @return is in raw format or not
 */
static const bool
isVolumeInRaw(const std::string& filePath)
{
    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        {},
        "qemu-img info \"" + filePath + "\"");
    if (r.exitCode != 0) {
        HexLogError(
            "failed to use qemu-img to probe the info of the volume, error: %s",
            r.stderrOutput.c_str());
        return false;
    }

    // parse the file format
    std::stringstream volumeInfo(r.stdoutOutput);
    std::string line;
    const std::string fileFormatLineTitle = "file format: ";
    // read the output line by line
    while (std::getline(volumeInfo, line)) {
        if (line.find(fileFormatLineTitle) == std::string::npos) {
            continue;
        }

        break;
    }
    if (line.empty()) {
        HexLogError("failed to parse the file format from\n%s", r.stdoutOutput.c_str());
        return false;
    }

    return (RemovePrefix(line, fileFormatLineTitle) == "raw");
}

/**
 * Get the virtual size of the volume.
 *
 * @param filePath the local full path of the file
 * @return is in raw format or not
 */
static const long long
getVolumeVirtualSize(const std::string& filePath)
{
    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        {},
        "qemu-img info \"" + filePath + "\"");
    if (r.exitCode != 0) {
        HexLogError(
            "failed to use qemu-img to probe the info of the volume, error: %s",
            r.stderrOutput.c_str());
        return 0;
    }

    // parse the virtual size
    std::stringstream volumeInfo(r.stdoutOutput);
    std::string line;
    const std::string virtualSizeLineTitle = "virtual size: ";
    // read the output line by line
    while (std::getline(volumeInfo, line)) {
        if (line.find(virtualSizeLineTitle) == std::string::npos) {
            continue;
        }

        break;
    }
    if (line.empty()) {
        HexLogError("failed to parse the virtual size from\n%s", r.stdoutOutput.c_str());
        return 0;
    }

    const std::size_t startPosition = line.find('(');
    if (startPosition == std::string::npos) {
        HexLogError("failed to parse the virtual size from\n%s", r.stdoutOutput.c_str());
        return 0;
    }
    const std::size_t endPosition = line.find(')');
    if (endPosition == std::string::npos) {
        HexLogError("failed to parse the virtual size from\n%s", r.stdoutOutput.c_str());
        return 0;
    }
    if (startPosition >= endPosition) {
        HexLogError("failed to parse the virtual size from\n%s", r.stdoutOutput.c_str());
        return 0;
    }

    const std::string data = line.substr(startPosition + 1, endPosition - startPosition - 1);
    const std::size_t bytesPosition = data.find("bytes");
    if (bytesPosition == std::string::npos) {
        HexLogError("failed to parse the virtual size from\n%s", r.stdoutOutput.c_str());
        return 0;
    }

    const std::string byteNumberString = Trim(data.substr(0, bytesPosition));
    long long byteNumber = 0;
    try {
        std::size_t pos;
        byteNumber = std::stoll(byteNumberString, &pos);
    } catch (const std::exception& e) {
        // failed to convert the output string to a long long
        HexLogError(
            "failed to parse the virtual size from %s, error: %s",
            byteNumberString.c_str(),
            e.what());
        return 0;
    }
    return byteNumber;
}

/**
 * Add admin_cli to the project for having sufficient permissions
 * to add the volume to the project.
 *
 * @param domain
 * @param project
 * @return successful or not
 */
static const bool
addAdminCliToProject(const std::string& domain, const std::string& project)
{
    const ExecSyncResult r = OpenstackExec(
        "role add --user admin_cli --project \"" + project
        + "\" --project-domain \"" + domain + "\" admin");
    if (r.exitCode != 0) {
        HexLogError("%s", r.stderrOutput.c_str());
        return false;
    }

    return true;
}

/**
 * Take an existing volume under control of Cinder.
 *
 * @param volumeType
 * @param filePath the full path of the file on the NFS share, e.g., <ip>:<file_full_path>
 * @param volumeName the display name for the incoming volume
 * @param domain
 * @param project
 * @param isBootable
 * @return volume ID, if blank, the manage failed
 */
static const std::string
manageExistingVolume(
    const std::string& volumeType,
    const std::string& filePath,
    const std::string& volumeName,
    const std::string& domain,
    const std::string& project,
    const bool& isBootable)
{
    std::string volumeBackendPool;
    if (volumeType == BUILTIN_VOLUME_TYPE) {
        volumeBackendPool = BUILTIN_VOLUME_BACKEND_POOL;
    } else {
        volumeBackendPool = volumeType + "@" + volumeType + "#" + volumeType;
    }

    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        ParseOpenstackCliAuth(),
        "cinder --os-project-domain-name \"" + domain
            + "\" --os-project-name \"" + project
            + "\" manage " + (isBootable ? "--bootable" : "")
            + " --name \"" + volumeName
            + "\" --volume-type \"" + volumeType
            + "\" \"" + volumeBackendPool + "\" \"" + filePath + "\"");
    if (r.exitCode != 0) {
        HexLogError("%s", r.stderrOutput.c_str());
        return "";
    }

    // parse the id
    std::stringstream volumeDetail(r.stdoutOutput);
    std::string line;
    // read the output line by line
    while (std::getline(volumeDetail, line)) {
        if (line.find("| id") == std::string::npos) {
            continue;
        }

        break;
    }
    if (line.empty()) {
        HexLogError("failed to parse the volume id from\n%s", r.stdoutOutput.c_str());
        return "";
    }

    const std::vector<std::string> lineData = hex_string_util::split(line, '|');
    std::string volumeId;
    try {
        volumeId = lineData.at(2);
    } catch (const std::out_of_range& e) {
        HexLogError("failed to parse the volume id from\n%s", r.stdoutOutput.c_str());
        return "";
    }

    return Trim(volumeId);
}

struct fileInfo : public mountPoint {
    std::string filePath;
};

static int
ManageExistingVolumeFromNfsMain(int argc, const char** argv)
{
    /**
     * [0]="manage_existing_from_nfs"
     * [1]=<source_nfs_storage_backend>
     * [2]=<file_path>
     * [3]=<volume_name>
     * [4]=<domain>
     * [5]=<project>
     * [6]=<YES|NO> perform virt-v2v conversion or not,
     * also implies the volume is bootable or not
     */
    if (argc > 7) {
        return CLI_INVALID_ARGS;
    }

    // gather the arguments
    std::string cmd = "";
    int index;

    std::string sourceNfsStorageBackend;
    std::string filePath;
    fileInfo fileExtraInfo;
    std::string volumeName;
    std::string domain;
    std::string project;
    bool performVolumeConversion;

    // [1]=<source_nfs_storage_backend>
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

    // [2]=<file_path>
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

    // [3]=<volume_name>
    if (!CliReadInputStr(
            argc,
            argv,
            3,
            "Specify volume name: ",
            &volumeName)) {
        CliPrint("Volume name is required");
        return CLI_INVALID_ARGS;
    }

    // [4]=<domain>
    cmd = HEX_SDK " os_list_domain_basic | awk '{print tolower($0)}'";
    if (CliMatchCmdHelper(argc, argv, 4, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    // [5]=<project>
    cmd = HEX_SDK " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 5, cmd, &index, &project, "Select project: ") != CLI_SUCCESS) {
        CliPrintf("Invalid project");
        return CLI_INVALID_ARGS;
    }

    // [6]=<YES|NO> perform virt-v2v conversion or not
    std::string performVolumeConversionAnswer;
    bool isAnswered = CliReadInputStr(
        argc,
        argv,
        6,
        "Enter 'YES' to perform virt-v2v conversion on the volume: ",
        &performVolumeConversionAnswer);
    performVolumeConversion = isAnswered && performVolumeConversionAnswer == "YES";

    std::cout << "fileInfo export: " << fileExtraInfo.exportPath << std::endl;
    std::cout << "fileInfo target: " << fileExtraInfo.target << std::endl;
    std::cout << "fileInfo path: " << fileExtraInfo.filePath << std::endl;

    /**
     * Perform the conversion.
     *
     * Only virt-v2v is used since we are highly likely
     * only migrating large volumes from other hypervisors.
     *
     * We only need to convert volumes not in the raw format.
     */
    if (performVolumeConversion && !isVolumeInRaw(fileExtraInfo.filePath)) {
        // check if we still have enough quota in the project to manage the volume
        const long long volumeSizeInBytes = getVolumeVirtualSize(fileExtraInfo.filePath);

        if (!IsQuotaGigabytesEnough(domain, project, volumeSizeInBytes)) {
            CliPrintf(
                "Project %s under domain %s does not have enough quota on resource %s, "
                "needed space for the volume is %lld",
                project.c_str(),
                domain.c_str(),
                "gigabytes",
                volumeSizeInBytes);
            return CLI_FAILURE;
        }

        if (!IsQuotaVolumesEnough(domain, project)) {
            CliPrintf(
                "Project %s under domain %s does not have enough quota on resource %s, "
                "needed space for the volume is %lld",
                project.c_str(),
                domain.c_str(),
                "volumes",
                volumeSizeInBytes);
            return CLI_FAILURE;
        }

        // TODO: perform the conversion and metadata parsing
    }

    if (!addAdminCliToProject(domain, project)) {
        HexLogError("failed to add admin_cli to the project to manage volumes");
        CliPrint("Not sufficient permissions to manage volumes in the project");
        return CLI_FAILURE;
    }

    const std::string volumeId = manageExistingVolume(
        sourceNfsStorageBackend,
        filePath,
        volumeName,
        domain,
        project,
        performVolumeConversion);
    if (volumeId.empty()) {
        HexLogError(
            "failed to manage the existing volume on nfs, "
            "source nfs storage backend: %s, file path: %s, "
            "volume name: %s, domain: %s, project: %s, "
            "perform volume conversion: %s",
            sourceNfsStorageBackend.c_str(),
            filePath.c_str(),
            volumeName.c_str(),
            domain.c_str(),
            project.c_str(),
            (performVolumeConversion ? "YES" : "NO"));
        CliPrint("Failed to manage the existing volume on NFS");
        return CLI_FAILURE;
    }

    std::cout << "volume id: " << volumeId << std::endl;
    // TODO: set volume metadata

    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_VOLUME,
    "manage_existing_from_nfs",
    ManageExistingVolumeFromNfsMain,
    NULL,
    "Manage an existing volume from a configured NFS volume backend. "
    "Perform needed conversions and set metadata if requested.",
    "manage_existing_from_nfs <source_nfs_storage_backend> "
    "<file_path> <volume_name> <domain> <project> "
    "<perform virt-v2v conversion or not>");

/**
 * Get volume types.
 *
 * @return a list of volume types, not filtered
 */
static const std::vector<std::string>
getVolumeTypes()
{
    const ExecSyncResult r = OpenstackExec("volume type list -f json");
    if (r.exitCode != 0) {
        HexLogError("%s", r.stderrOutput.c_str());
        return {};
    }

    // parse the output
    std::string jsonError;
    const json11::Json volumeTypeList = json11::Json::parse(r.stdoutOutput, jsonError);
    if (!jsonError.empty()) {
        HexLogError("%s", jsonError.c_str());
        return {};
    }
    const json11::Json::array& volumeTypes = volumeTypeList.array_items();
    std::vector<std::string> result;
    for (const json11::Json& t : volumeTypes) {
        if (!t["Name"].is_string()) {
            continue;
        }
        result.push_back(t["Name"].string_value());
    }

    return result;
}

struct volumeInfo {
    std::string id;
    std::string name;
};

/**
 * Get the list of volumes under a project under a domain.
 *
 * @param domain
 * @param project
 * @return a list of volumes with id and name
 */
static const std::vector<volumeInfo>
getVolumes(const std::string& domain, const std::string& project)
{
    const ExecSyncResult r = OpenstackExec(
        "volume list --project \"" + project
        + "\" --project-domain \"" + domain
        + "\" -f json");
    if (r.exitCode != 0) {
        HexLogError("%s", r.stderrOutput.c_str());
        return {};
    }

    // parse the output
    std::string jsonError;
    const json11::Json volumeList = json11::Json::parse(r.stdoutOutput, jsonError);
    if (!jsonError.empty()) {
        HexLogError("%s", jsonError.c_str());
        return {};
    }
    const json11::Json::array& volumes = volumeList.array_items();
    std::vector<volumeInfo> result;
    for (const json11::Json& v : volumes) {
        if (!v["ID"].is_string()) {
            continue;
        }

        volumeInfo i = {
            .id = v["ID"].string_value(),
        };

        if (v["Name"].is_string()) {
            i.name = v["Name"].string_value();
        }

        result.push_back(i);
    }

    return result;
}

static int
MoveVolumeToBackendMain(int argc, const char** argv)
{
    /**
     * [0]="move"
     * [1]=<domain>
     * [2]=<project>
     * [3]=<volume_id>
     * [4]=<destination_volume_type>
     */
    if (argc > 5) {
        return CLI_INVALID_ARGS;
    }

    std::string cmd = "";
    int index;

    std::string domain;
    std::string project;
    std::string volumeId;
    std::string destinationVolumeType;

    // [1] domain
    cmd = HEX_SDK " os_list_domain_basic | awk '{print tolower($0)}'";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    // [2] project
    cmd = HEX_SDK " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &project, "Select project: ") != CLI_SUCCESS) {
        CliPrintf("Invalid project");
        return CLI_INVALID_ARGS;
    }

    // [3] volume_id
    const std::vector<volumeInfo> volumes = getVolumes(domain, project);
    CliList volumeList;
    CliList volumeDescList;
    for (const volumeInfo& v : volumes) {
        volumeList.push_back(v.id);
        volumeDescList.push_back(v.id + " " + v.name);
    }
    if (CliMatchListDescHelper(
            argc,
            argv,
            3,
            volumeList,
            volumeDescList,
            &index,
            &volumeId,
            "Select the volume ID: ")
        != CLI_SUCCESS) {
        CliPrintf("Invalid volume ID");
        return CLI_INVALID_ARGS;
    }

    // [4] destination_volume_type
    const std::string volumeSrouceType = getVolumeTypeById(volumeId);
    const std::vector<std::string> volumeTypes = getVolumeTypes();
    CliList typeList;
    // filter out undesired types
    for (const std::string& t : volumeTypes) {
        if (t == "__DEFAULT__") {
            continue;
        }
        if (t == volumeSrouceType) {
            /**
             * Setting the destination volume type the same
             * as the source volume type is meaningless.
             */
            continue;
        }

        typeList.push_back(t);
    }

    if (CliMatchListHelper(
            argc,
            argv,
            4,
            typeList,
            &index,
            &destinationVolumeType,
            "Select the destination volume type: ")
        != CLI_SUCCESS) {
        CliPrintf("Invalid volume type");
        return CLI_INVALID_ARGS;
    }

    const ExecSyncResult r = ExecBashSync(
        0,
        true,
        true,
        ParseOpenstackCliAuth(),
        "cinder retype --migration-policy on-demand \""
            + volumeId + "\" \"" + destinationVolumeType + "\"");
    if (r.exitCode != 0) {
        HexLogError("%s", r.stderrOutput.c_str());
        std::cout << "Output: " << std::endl
                  << r.stdoutOutput << std::endl;
        std::cout << "Error: " << std::endl
                  << r.stderrOutput << std::endl;
        return CLI_FAILURE;
    }

    std::cout << "Output: " << std::endl
              << r.stdoutOutput << std::endl;
    return CLI_SUCCESS;
}

CLI_MODE_COMMAND(
    CLI_COMMAND_IAAS_VOLUME,
    "move",
    MoveVolumeToBackendMain,
    NULL,
    "Move a volume to a volume backend.",
    "move <domain> <project> <volume_id> <destination_volume_type>");
