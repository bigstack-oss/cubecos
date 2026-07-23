// CUBE SDK

#include <cctype>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <vector>
#include <unistd.h>
#include <hex/log.h>
#include <hex/filesystem.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/config_module.h>
#include <hex/dryrun.h>
#include <hex/tempfile.h>
#include <third_party/json11.hpp>

static const char GPU_CONFIG_DIR[]  = "/etc/cube/cos/gpu";
static const char GPU_CONFIG_FILE[] = "/etc/cube/cos/gpu/config.json";
static const char NVIDIA_SMI[]      = "/usr/bin/nvidia-smi";
static const char NVIDIA_SRIOV[]    = "/usr/lib/nvidia/sriov-manage";
static const char PCI_DEVICES_DIR[] = "/sys/bus/pci/devices";
static const char NOVA_GPU_CONF[]   = "/etc/nova/nova.d/gpu.conf";

// nvidia-smi reports an 8-char PCI domain (00000000:bb:ss.f) while sysfs
// uses a 4-char one (0000:bb:ss.f). Addresses already in sysfs form are
// returned unchanged (lowercased).
static std::string
SysfsPciAddr(const std::string& pciAddress)
{
    std::string addr = pciAddress;

    if (addr.find(':') == 8) {
        addr = addr.substr(4);
    }

    for (size_t i = 0; i < addr.size(); i++) {
        addr[i] = tolower(addr[i]);
    }

    return addr;
}

static bool
WriteSysfs(const std::string& path, const std::string& value)
{
    std::ofstream stream(path);
    if (!stream.is_open()) {
        return false;
    }
    stream << value;
    stream.flush();
    return stream.good();
}

// Expands validated profiles ({id, count}[]) into the per-VF assignment
// plan: one profile id per VF slot, in request order.
static std::vector<int>
BuildVfAssignmentPlan(const json11::Json& profiles)
{
    std::vector<int> plan;

    for (const json11::Json& profile : profiles.array_items()) {
        const int id = (int)profile["id"].number_value();
        const int count = (int)profile["count"].number_value();
        for (int i = 0; i < count; i++) {
            plan.push_back(id);
        }
    }

    return plan;
}

// sriov-manage briefly requests the NVIDIA driver's unbindLock before
// enabling/disabling VFs. If another NVML client (e.g. cube-cos-api's GPU
// status API) happens to hold the device open at that exact moment, the
// request is transiently refused with "Cannot obtain unbindLock" - retrying
// briefly clears up that race. A failure that isn't this specific message
// (bad address, driver unloaded, etc.) is not retried and fails immediately.
static bool
RunSriovManageWithRetry(const char* op, const std::string& sysfsAddr)
{
    static const int MAX_ATTEMPTS = 5;

    for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
        const std::string output = HexUtilPOpen(
            "%s %s %s 2>&1; echo |__HEX_RC_$?__|", NVIDIA_SRIOV, op, sysfsAddr.c_str());

        const size_t marker = output.rfind("|__HEX_RC_");
        const int rc = (marker != std::string::npos) ? atoi(output.c_str() + marker + 10) : -1;

        if (rc == 0) {
            return true;
        }

        if (output.find("Cannot obtain unbindLock") == std::string::npos) {
            HexLogError("gpu_resource_set: sriov-manage %s %s failed: %s",
                        op, sysfsAddr.c_str(), output.c_str());
            return false;
        }

        if (attempt == MAX_ATTEMPTS) {
            HexLogError("gpu_resource_set: sriov-manage %s %s: unbindLock still busy after %d attempts",
                        op, sysfsAddr.c_str(), MAX_ATTEMPTS);
            return false;
        }

        HexLogWarning("gpu_resource_set: sriov-manage %s %s: unbindLock busy, retrying (%d/%d)",
                       op, sysfsAddr.c_str(), attempt, MAX_ATTEMPTS);
        sleep(1);
    }

    return false;
}

// Best-effort teardown after a failed apply: releases the VFs via
// sriov-manage -d, which also clears each VF's current_vgpu_type
// internally. A raw sysfs write to sriov_numvfs is rejected by the driver
// unconditionally (confirmed on cn13 hardware) - disabling VFs must go
// through sriov-manage's unbindLock handshake, same as enabling them.
static void
TeardownSriov(const std::string& sysfsAddr)
{
    RunSriovManageWithRetry("-d", sysfsAddr);
}

// Enables the PF's VFs and writes each requested profile id into that many
// VFs' current_vgpu_type - the write is what actually carves the vGPU.
// profiles must already be validated. sriov-manage -e is idempotent for an
// already-enabled GPU (verified on cn13, 2026-07-17), so this is safe to
// re-run from boot-time Commit().
static bool
ApplySriovVgpu(const std::string& pciAddress, const json11::Json& profiles)
{
    const std::string sysfsAddr = SysfsPciAddr(pciAddress);

    if (!RunSriovManageWithRetry("-e", sysfsAddr)) {
        return false;
    }

    const std::vector<int> plan = BuildVfAssignmentPlan(profiles);

    for (size_t vf = 0; vf < plan.size(); vf++) {
        const std::string typePath = std::string(PCI_DEVICES_DIR) + "/" + sysfsAddr +
            "/virtfn" + std::to_string(vf) + "/nvidia/current_vgpu_type";

        if (!WriteSysfs(typePath, std::to_string(plan[vf]))) {
            HexLogError("gpu_resource_set: failed to set vGPU type %d on %s/virtfn%d",
                        plan[vf], sysfsAddr.c_str(), (int)vf);
            TeardownSriov(sysfsAddr);
            return false;
        }
    }

    return true;
}

// A PF counts as applied when its VFs are enabled and at least one VF
// already carries a vGPU type.
static bool
SriovVgpuApplied(const std::string& sysfsAddr)
{
    std::ifstream numvfsStream(std::string(PCI_DEVICES_DIR) + "/" + sysfsAddr + "/sriov_numvfs");
    long numvfs = 0;
    if (!(numvfsStream >> numvfs) || numvfs <= 0) {
        return false;
    }

    for (long i = 0; i < numvfs; i++) {
        std::ifstream typeStream(std::string(PCI_DEVICES_DIR) + "/" + sysfsAddr +
                                 "/virtfn" + std::to_string(i) + "/nvidia/current_vgpu_type");
        long vgpuType = 0;
        if ((typeStream >> vgpuType) && vgpuType != 0) {
            return true;
        }
    }

    return false;
}

// Parses `nvidia-smi vgpu -s -v` output into a map of vGPU type id (decimal)
// -> full type name. Blocks look like:
//   vGPU Type ID                      : 0x5ef
//       Name                          : NVIDIA RTX Pro 6000 Blackwell DC-3Q
static std::map<int, std::string>
ParseVgpuTypeNames(const std::string& smiOutput)
{
    std::map<int, std::string> names;
    std::istringstream stream(smiOutput);
    std::string line;
    int currentId = -1;

    while (std::getline(stream, line)) {
        const size_t colon = line.find(':');
        if (colon == std::string::npos) {
            continue;
        }

        std::string key = line.substr(0, colon);
        key.erase(0, key.find_first_not_of(" \t"));
        key.erase(key.find_last_not_of(" \t") + 1);

        std::string value = line.substr(colon + 1);
        value.erase(0, value.find_first_not_of(" \t"));
        value.erase(value.find_last_not_of(" \t\r") + 1);

        if (key == "vGPU Type ID") {
            currentId = (int)strtol(value.c_str(), NULL, 16);
        } else if (key == "Name" && currentId >= 0 && !value.empty()) {
            names[currentId] = value;
            currentId = -1;
        }
    }

    return names;
}

static std::map<int, std::string>
GetVgpuTypeNames(const char* gpuId)
{
    return ParseVgpuTypeNames(HexUtilPOpen("%s vgpu -s -v -i %s", NVIDIA_SMI, gpuId));
}

// Derives the Nova PCI alias for a profile following the #894 convention:
// lowercase the full vGPU type name, map non-alphanumerics to '_' (squeezing
// repeats), then append "_<id>".
// e.g. "NVIDIA H100 1-10C" + 100 -> "nvidia_h100_1_10c_100"
static std::string
ProfileAlias(const std::string& fullName, int profileId)
{
    std::string alias;

    for (size_t i = 0; i < fullName.size(); i++) {
        const unsigned char c = fullName[i];
        if (isalnum(c)) {
            alias += tolower(c);
        } else if (!alias.empty() && alias.back() != '_') {
            alias += '_';
        }
    }

    if (alias.empty() || alias.back() != '_') {
        alias += '_';
    }

    return alias + std::to_string(profileId);
}

struct SriovVf {
    std::string address;    // sysfs form, e.g. 0001:c8:00.2
    std::string vendorId;   // e.g. 10de
    std::string productId;  // e.g. 2bb5
};

// Reads a sysfs id token (e.g. "0x10de") and strips the 0x prefix.
static std::string
ReadSysfsId(const std::string& path)
{
    std::ifstream stream(path);
    std::string token;

    if (!(stream >> token)) {
        return "";
    }

    if (token.compare(0, 2, "0x") == 0) {
        token = token.substr(2);
    }

    return token;
}

// Resolves the first `count` VFs of a PF from sysfs: PCI address (via the
// virtfnN symlink) plus vendor/product ids read from the VF itself (not
// hardcoded - VF ids are device specific).
static bool
GetSriovVfs(const std::string& sysfsAddr, size_t count, std::vector<SriovVf>* vfs)
{
    for (size_t i = 0; i < count; i++) {
        const std::string link = std::string(PCI_DEVICES_DIR) + "/" + sysfsAddr +
            "/virtfn" + std::to_string(i);

        char target[256];
        const ssize_t len = readlink(link.c_str(), target, sizeof(target) - 1);
        if (len <= 0) {
            return false;
        }
        target[len] = '\0';

        std::string address(target);
        const size_t slash = address.find_last_of('/');
        if (slash != std::string::npos) {
            address = address.substr(slash + 1);
        }

        SriovVf vf;
        vf.address = address;
        vf.vendorId = ReadSysfsId(std::string(PCI_DEVICES_DIR) + "/" + address + "/vendor");
        vf.productId = ReadSysfsId(std::string(PCI_DEVICES_DIR) + "/" + address + "/device");
        if (vf.vendorId.empty() || vf.productId.empty()) {
            return false;
        }

        vfs->push_back(vf);
    }

    return true;
}

// Builds the /etc/nova/nova.d/gpu.conf content from config.json entries:
// one [pci] alias per profile and one passthrough_whitelist per assigned VF
// of every sriovVgpu GPU. Regenerating everything from the truth file means
// entries for GPUs switched away from sriovVgpu disappear without any
// dedicated cleanup logic.
static std::string
BuildNovaGpuConfContent(const json11::Json& gpuConfig,
                        const std::map<std::string, std::vector<SriovVf>>& vfsByGpuId)
{
    std::string content =
        "# Generated by hex_config (gpu_resource_set / gpu Commit). Do not edit.\n"
        "[pci]\n";

    for (const json11::Json& entry : gpuConfig.array_items()) {
        if (!entry["type"].is_string() || entry["type"].string_value() != "sriovVgpu") {
            continue;
        }

        const std::map<std::string, std::vector<SriovVf>>::const_iterator vfsIt =
            vfsByGpuId.find(entry["id"].string_value());
        if (vfsIt == vfsByGpuId.end() || vfsIt->second.empty()) {
            continue;
        }

        const std::vector<SriovVf>& vfs = vfsIt->second;

        for (const json11::Json& profile : entry["profiles"].array_items()) {
            if (!profile["alias"].is_string()) {
                continue;
            }
            content += "alias = { \"name\": \"" + profile["alias"].string_value() +
                       "\", \"device_type\": \"type-VF\", \"vendor_id\": \"" + vfs[0].vendorId +
                       "\", \"product_id\": \"" + vfs[0].productId + "\" }\n";
        }

        for (size_t i = 0; i < vfs.size(); i++) {
            content += "passthrough_whitelist = { \"vendor_id\": \"" + vfs[i].vendorId +
                       "\", \"product_id\": \"" + vfs[i].productId +
                       "\", \"address\": \"" + vfs[i].address + "\", \"managed\": \"no\" }\n";
        }
    }

    return content;
}

// Regenerates /etc/nova/nova.d/gpu.conf from config.json (the single source
// of truth). All nova services load /etc/nova/nova.d via --config-dir, so
// the drop-in takes effect on the next nova (re)start.
static bool
WriteNovaGpuConf(void)
{
    std::ifstream configStream(GPU_CONFIG_FILE);
    std::stringstream buffer;
    buffer << configStream.rdbuf();

    std::string jsonError;
    const json11::Json gpuConfig = json11::Json::parse(buffer.str(), jsonError);
    if (!jsonError.empty()) {
        HexLogError("Failed to parse GPU config file %s: %s", GPU_CONFIG_FILE, jsonError.c_str());
        return false;
    }

    std::map<std::string, std::vector<SriovVf>> vfsByGpuId;

    for (const json11::Json& entry : gpuConfig.array_items()) {
        if (!entry["type"].is_string() || entry["type"].string_value() != "sriovVgpu") {
            continue;
        }

        const std::string gpuId = entry["id"].string_value();

        if (!entry["pciAddress"].is_string() || entry["pciAddress"].string_value().empty()) {
            HexLogError("GPU %s has type sriovVgpu but no recorded pciAddress", gpuId.c_str());
            return false;
        }

        size_t assigned = 0;
        for (const json11::Json& profile : entry["profiles"].array_items()) {
            assigned += (size_t)profile["count"].number_value();
        }

        std::vector<SriovVf> vfs;
        if (!GetSriovVfs(SysfsPciAddr(entry["pciAddress"].string_value()), assigned, &vfs)) {
            HexLogError("Failed to resolve VFs of GPU %s for %s", gpuId.c_str(), NOVA_GPU_CONF);
            return false;
        }

        vfsByGpuId[gpuId] = vfs;
    }

    HexTempFile tmpFile;
    if (tmpFile.fd() < 0) {
        HexLogError("Failed to create a temporary file for %s", NOVA_GPU_CONF);
        return false;
    }
    tmpFile.close();

    std::ofstream out(tmpFile.path());
    out << BuildNovaGpuConfContent(gpuConfig, vfsByGpuId);
    out.flush();
    if (!out.good()) {
        HexLogError("Failed to write %s", tmpFile.path());
        return false;
    }
    out.close();

    // HexTempFile is created 0600; nova (non-root) must be able to read the
    // drop-in, and it carries no secrets.
    if (HexUtilSystemF(0, 0, "mv %s %s && chmod 644 %s",
                       tmpFile.path(), NOVA_GPU_CONF, NOVA_GPU_CONF) != 0) {
        HexLogError("Failed to install %s", NOVA_GPU_CONF);
        return false;
    }

    return true;
}

// Looks up GPU gpuId via gpu_device_list, the single source of truth for
// GPU id/name/type/pciAddress - it already unions live nvidia-smi data with
// `config.json` entries, specifically for GPUs no longer visible to nvidia-smi
// after bound to vfio-pci.
// Returns json11::Json() (null) if the command fails or the GPU isn't found.
static json11::Json
FindGpuDevice(const char* gpuId)
{
    const std::string deviceListJson = HexUtilPOpen(HEX_SDK " gpu_device_list");

    std::string jsonError;
    const json11::Json deviceList = json11::Json::parse(deviceListJson, jsonError);

    if (!jsonError.empty()) {
        return json11::Json();
    }

    for (const json11::Json& entry : deviceList.array_items()) {
        if (entry["id"].is_string() && entry["id"].string_value() == gpuId) {
            return entry;
        }
    }

    return json11::Json();
}

// Validates the profiles argument for sriovVgpu/migBackedVgpu:
// - format: a non-empty JSON array of { id, count } objects with unique
//   non-negative-integer ids and positive-integer counts
// - existence: every id must be an available profile of the requested type
//   on this GPU, as reported by gpu_vgpu_profile_list
// - capacity (SR-IOV only): each vGPU instance occupies one VF, so the
//   total requested count must fit within the PF's sriov_totalvfs
static bool
ValidateVgpuProfiles(const char* gpuId, const char* newType, const char* profiles, const std::string& pciAddress)
{
    std::string jsonError;
    const json11::Json parsed = json11::Json::parse(profiles, jsonError);

    if (!jsonError.empty() || !parsed.is_array() || parsed.array_items().empty()) {
        HexLogError("gpu_resource_set: profiles must be a non-empty JSON array of { id, count } objects");
        return false;
    }

    std::set<int> requestedIds;
    long requestedTotal = 0;

    for (const json11::Json& profile : parsed.array_items()) {
        if (!profile.is_object() || !profile["id"].is_number() || !profile["count"].is_number()) {
            HexLogError("gpu_resource_set: each profile must be an object with a numeric id and count");
            return false;
        }

        const double id = profile["id"].number_value();
        const double count = profile["count"].number_value();

        if (id != std::floor(id) || id < 0) {
            HexLogError("gpu_resource_set: profile id must be a non-negative integer");
            return false;
        }

        if (count != std::floor(count) || count < 1) {
            HexLogError("gpu_resource_set: profile count must be a positive integer");
            return false;
        }

        if (!requestedIds.insert((int)id).second) {
            HexLogError("gpu_resource_set: duplicate profile id %d", (int)id);
            return false;
        }

        requestedTotal += (long)count;
    }

    const std::string profileListJson = HexUtilPOpen(HEX_SDK " gpu_vgpu_profile_list %s", gpuId);

    const json11::Json profileList = json11::Json::parse(profileListJson, jsonError);
    if (!jsonError.empty()) {
        HexLogError("gpu_resource_set: failed to list vGPU profiles for GPU %s", gpuId);
        return false;
    }

    const char* listKey = (strcmp(newType, "sriovVgpu") == 0) ? "sriov" : "migBacked";

    std::set<int> availableIds;
    for (const json11::Json& profile : profileList[listKey].array_items()) {
        if (profile["id"].is_number()) {
            availableIds.insert((int)profile["id"].number_value());
        }
    }

    for (const int id : requestedIds) {
        if (availableIds.find(id) == availableIds.end()) {
            HexLogError("gpu_resource_set: profile id %d is not a valid %s profile for GPU %s", id, newType, gpuId);
            return false;
        }
    }

    if (strcmp(newType, "sriovVgpu") == 0 && !pciAddress.empty()) {
        const std::string sysfsAddr = SysfsPciAddr(pciAddress);

        // An unreadable sriov_totalvfs fails the check rather than skipping
        // it - a missing/unreadable required precondition is not the same
        // as "capacity confirmed sufficient".
        std::ifstream totalVfsStream(std::string(PCI_DEVICES_DIR) + "/" + sysfsAddr + "/sriov_totalvfs");
        long totalVfs = 0;
        if (!(totalVfsStream >> totalVfs)) {
            HexLogError("gpu_resource_set: could not read sriov_totalvfs for GPU %s", gpuId);
            return false;
        }
        if (requestedTotal > totalVfs) {
            HexLogError("gpu_resource_set: requested %ld vGPU(s) exceeds the %ld VF(s) available on GPU %s",
                        requestedTotal, totalVfs, gpuId);
            return false;
        }
    }

    // TODO(#905): validate MIG-backed capacity constraints (per-profile
    // vmCountLimit and the device VRAM budget).

    return true;
}

static void
ResourceSetUsage(void)
{
    fprintf(stderr, "Usage: %s gpu_resource_set <gpu_id> <new_type> [profiles]\n", HexLogProgramName());
}

static int
ResourceSetMain(int argc, char* argv[])
{
    /*
     * [0]="gpu_resource_set", [1]=<gpu_id>, [2]=<new_type>, [3]=[profiles]
     */
    if (argc < 3 || argc > 4) {
        HexLogError("gpu_resource_set: invalid number of arguments");
        ResourceSetUsage();
        return EXIT_FAILURE;
    }

    const char* gpuId   = argv[1];
    const char* newType  = argv[2];
    const char* profiles = (argc == 4) ? argv[3] : "";

    if (strcmp(newType, "pgpu") != 0 &&
        strcmp(newType, "sriovVgpu") != 0 &&
        strcmp(newType, "migBackedVgpu") != 0) {
        HexLogError("gpu_resource_set: invalid type '%s'. Must be one of: pgpu, sriovVgpu, migBackedVgpu", newType);
        return EXIT_FAILURE;
    }

    if (strcmp(newType, "pgpu") == 0 && profiles[0] != '\0') {
        HexLogError("gpu_resource_set: profiles is not allowed when new_type is pgpu");
        return EXIT_FAILURE;
    }

    if (
        (strcmp(newType, "sriovVgpu") == 0 || strcmp(newType, "migBackedVgpu") == 0) &&
        profiles[0] == '\0'
    ) {
        HexLogError("gpu_resource_set: profiles is required when new_type is sriovVgpu or migBackedVgpu");
        return EXIT_FAILURE;
    }

    if (access(GPU_CONFIG_FILE, F_OK) != 0) {
        HexLogError("gpu_resource_set: GPU config file not found at %s", GPU_CONFIG_FILE);
        return EXIT_FAILURE;
    }

    if (HexUtilSystemF(0, 0, HEX_SDK " gpu_resource_set_check %s %s %s", gpuId, newType, profiles) != 0) {
        HexLogError("gpu_resource_set: pre-condition check failed for GPU %s", gpuId);
        return EXIT_FAILURE;
    }

    // Existence already confirmed by gpu_resource_set_validate above; this
    // is purely to fetch name/pciAddress for binding and persisting.
    const json11::Json device = FindGpuDevice(gpuId);
    if (!device.is_object()) {
        HexLogError("gpu_resource_set: GPU %s not found", gpuId);
        return EXIT_FAILURE;
    }

    const std::string name = device["name"].is_string() ? device["name"].string_value() : "";
    const std::string pciAddress = device["pciAddress"].is_string() ? device["pciAddress"].string_value() : "";
    if (name.empty() || pciAddress.empty()) {
        HexLogError("gpu_resource_set: GPU %s is missing name/pciAddress in the config file", gpuId);
        return EXIT_FAILURE;
    }

    // Validate profiles before gpu_unset_current_type below so that a bad
    // request cannot tear down the GPU's existing configuration.
    if ((strcmp(newType, "sriovVgpu") == 0 || strcmp(newType, "migBackedVgpu") == 0) &&
        !ValidateVgpuProfiles(gpuId, newType, profiles, pciAddress)) {
        return EXIT_FAILURE;
    }

    if (HexUtilSystemF(0, 0, HEX_SDK " gpu_unset_current_type %s", gpuId) != 0) {
        HexLogError("gpu_resource_set: failed to unset current type for GPU %s", gpuId);
        return EXIT_FAILURE;
    }

    if (strcmp(newType, "pgpu") == 0) {
        if (HexUtilSystemF(0, 0, HEX_SDK " gpu_bind_vfio_pci %s", pciAddress.c_str()) != 0) {
            HexLogError("gpu_resource_set: failed to bind GPU %s to vfio-pci for passthrough", gpuId);
            return EXIT_FAILURE;
        }

        HexTempFile tmpFile;
        if (tmpFile.fd() < 0) {
            HexLogError("gpu_resource_set: failed to create a temporary file");
            return EXIT_FAILURE;
        }
        tmpFile.close();

        if (HexUtilSystemF(0, 0,
                "jq -c --arg id \"%s\" --arg name \"%s\" --arg pciAddress \"%s\" "
                "'map(select(.id != $id)) + [{id:$id, name:$name, type:\"pgpu\", pciAddress:$pciAddress, profiles:null}]' %s > %s",
                gpuId, name.c_str(), pciAddress.c_str(), GPU_CONFIG_FILE, tmpFile.path()) != 0) {
            HexLogError("gpu_resource_set: failed to build updated GPU config for %s", gpuId);
            return EXIT_FAILURE;
        }

        if (HexUtilSystemF(0, 0, "mv %s %s", tmpFile.path(), GPU_CONFIG_FILE) != 0) {
            HexLogError("gpu_resource_set: failed to persist GPU %s config", gpuId);
            return EXIT_FAILURE;
        }

        // Switching a card away from sriovVgpu must also drop its stale
        // alias/whitelist entries from the Nova drop-in (regenerated from
        // the just-updated truth file). Nodes that never had a drop-in are
        // left untouched.
        if (access(NOVA_GPU_CONF, F_OK) == 0) {
            if (!WriteNovaGpuConf()) {
                HexLogError("gpu_resource_set: failed to regenerate %s for GPU %s", NOVA_GPU_CONF, gpuId);
                return EXIT_FAILURE;
            }

            if (HexUtilSystemF(0, 0, HEX_CFG " restart_nova") != 0) {
                HexLogError("gpu_resource_set: failed to restart nova services for GPU %s", gpuId);
                return EXIT_FAILURE;
            }
        }

        HexLogInfo("gpu_resource_set: successfully updated GPU %s to pgpu", gpuId);
        return EXIT_SUCCESS;
    } else if (strcmp(newType, "sriovVgpu") == 0) {
        // Existence of every requested id was confirmed by
        // ValidateVgpuProfiles above; parse cannot fail here.
        std::string jsonError;
        const json11::Json requested = json11::Json::parse(profiles, jsonError);

        // Enrich the requested {id, count} pairs with name/alias for
        // persistence (#894 schema: {id, name, count, alias}).
        const std::map<int, std::string> typeNames = GetVgpuTypeNames(gpuId);

        json11::Json::array persistedProfiles;
        for (const json11::Json& profile : requested.array_items()) {
            const int id = (int)profile["id"].number_value();

            const std::map<int, std::string>::const_iterator nameIt = typeNames.find(id);
            if (nameIt == typeNames.end()) {
                HexLogError("gpu_resource_set: failed to resolve the vGPU type name of profile %d on GPU %s",
                            id, gpuId);
                return EXIT_FAILURE;
            }

            persistedProfiles.push_back(json11::Json::object {
                { "id", id },
                { "name", nameIt->second },
                { "count", (int)profile["count"].number_value() },
                { "alias", ProfileAlias(nameIt->second, id) },
            });
        }

        if (!ApplySriovVgpu(pciAddress, requested)) {
            HexLogError("gpu_resource_set: failed to apply SR-IOV vGPU partitioning on GPU %s", gpuId);
            return EXIT_FAILURE;
        }

        HexTempFile tmpFile;
        if (tmpFile.fd() < 0) {
            HexLogError("gpu_resource_set: failed to create a temporary file");
            return EXIT_FAILURE;
        }
        tmpFile.close();

        const std::string profilesDump = json11::Json(persistedProfiles).dump();

        if (HexUtilSystemF(0, 0,
                "jq -c --arg id \"%s\" --arg name \"%s\" --arg pciAddress \"%s\" --argjson profiles '%s' "
                "'map(select(.id != $id)) + [{id:$id, name:$name, type:\"sriovVgpu\", pciAddress:$pciAddress, profiles:$profiles}]' %s > %s",
                gpuId, name.c_str(), pciAddress.c_str(), profilesDump.c_str(),
                GPU_CONFIG_FILE, tmpFile.path()) != 0) {
            HexLogError("gpu_resource_set: failed to build updated GPU config for %s", gpuId);
            return EXIT_FAILURE;
        }

        if (HexUtilSystemF(0, 0, "mv %s %s", tmpFile.path(), GPU_CONFIG_FILE) != 0) {
            HexLogError("gpu_resource_set: failed to persist GPU %s config", gpuId);
            return EXIT_FAILURE;
        }

        if (!WriteNovaGpuConf()) {
            HexLogError("gpu_resource_set: failed to regenerate %s for GPU %s", NOVA_GPU_CONF, gpuId);
            return EXIT_FAILURE;
        }

        if (HexUtilSystemF(0, 0, HEX_CFG " restart_nova") != 0) {
            HexLogError("gpu_resource_set: failed to restart nova services for GPU %s", gpuId);
            return EXIT_FAILURE;
        }

        HexLogInfo("gpu_resource_set: successfully updated GPU %s to sriovVgpu", gpuId);
        return EXIT_SUCCESS;
    } else if (strcmp(newType, "migBackedVgpu") == 0) {
        // TODO(#905)
    }

    HexLogError("gpu_resource_set: unhandled type %s", newType);
    return EXIT_FAILURE;
}

static bool
Commit(bool modified, int dryLevel)
{
    HEX_DRYRUN_BARRIER(dryLevel, true);

    if (HexMakeDir(GPU_CONFIG_DIR, "root", "root", 0755) != 0) {
        HexLogError("Failed to create GPU config directory: %s", GPU_CONFIG_DIR);
        return false;
    }

    if (access(GPU_CONFIG_FILE, F_OK) != 0) {
        /* Data in `config.json` is an array with the following data structure:
        {
          id: string
          name: string
          type: 'pgpu' | 'sriovVgpu' | 'migBackedVgpu'
          pciAddress: string
          profiles: {
            id: number
            count: number
            alias: string
          }[] | null
        }
        */
        HexUtilSystemF(0, 0, "echo '[]' > %s", GPU_CONFIG_FILE);
        return true;
    }

    // Hardware driver bindings (e.g. vfio-pci passthrough) do not survive a
    // reboot or an OS upgrade on their own, but Commit() runs on every boot
    // (via bootstrap) and every settings commit, so re-apply persisted
    // policy here rather than relying on static modprobe.d config.
    std::ifstream configStream(GPU_CONFIG_FILE);
    std::stringstream buffer;
    buffer << configStream.rdbuf();

    std::string jsonError;
    const json11::Json gpuConfig = json11::Json::parse(buffer.str(), jsonError);
    if (!jsonError.empty()) {
        HexLogError("Failed to parse GPU config file %s: %s", GPU_CONFIG_FILE, jsonError.c_str());
        return false;
    }

    bool hasSriovVgpu = false;

    for (const json11::Json& entry : gpuConfig.array_items()) {
        if (!entry["id"].is_string() || !entry["type"].is_string()) {
            continue;
        }

        const std::string id = entry["id"].string_value();
        const std::string type = entry["type"].string_value();

        if (type == "pgpu") {
            if (!entry["pciAddress"].is_string() || entry["pciAddress"].string_value().empty()) {
                HexLogError("GPU %s has type pgpu but no recorded pciAddress; cannot re-apply binding", id.c_str());
                return false;
            }

            const std::string pciAddress = entry["pciAddress"].string_value();

            // Re-apply by PCI bus address, not by GPU UUID: once a GPU is
            // bound to vfio-pci it is no longer enumerable by nvidia-smi,
            // so a UUID-based lookup would fail here on every Commit() run
            // after the first.
            if (HexUtilSystemF(0, 0, HEX_SDK " gpu_bind_vfio_pci %s", pciAddress.c_str()) != 0) {
                HexLogError("Failed to re-apply pgpu passthrough binding for GPU %s", id.c_str());
                return false;
            }
        } else if (type == "sriovVgpu") {
            // GPU is optional hardware: a single card's sysfs state being
            // unreadable or an apply hiccup should not fail Commit() for
            // the whole node and force a reboot. Log and move on to the
            // next entry instead.
            if (!entry["pciAddress"].is_string() || entry["pciAddress"].string_value().empty()) {
                HexLogError("GPU %s has type sriovVgpu but no recorded pciAddress; cannot re-apply partitioning", id.c_str());
                continue;
            }

            const std::string pciAddress = entry["pciAddress"].string_value();

            // VF enablement and per-VF vGPU types are sysfs state and do
            // not survive a reboot. Skip GPUs that still carry an applied
            // layout - this also keeps runtime commits from disturbing
            // vGPUs attached to running VMs.
            if (!SriovVgpuApplied(SysfsPciAddr(pciAddress))) {
                if (!ApplySriovVgpu(pciAddress, entry["profiles"])) {
                    HexLogError("Failed to re-apply sriovVgpu partitioning for GPU %s", id.c_str());
                    continue;
                }
            }

            hasSriovVgpu = true;
        }
        // TODO(#905): re-apply migBackedVgpu once gpu_resource_set supports it.
    }

    // The drop-in's content derives solely from config.json, which does not
    // change across reboots, so no nova restart is needed here -
    // regeneration is self-healing only (e.g. after a lost/stale gpu.conf).
    // Also regenerate when a drop-in exists but no sriovVgpu entry remains,
    // so entries of cards switched away from sriovVgpu don't linger.
    //
    // A regen failure here means Nova's GPU scheduling info may be stale,
    // not that the node's policy apply should fail and force a reboot.
    if ((hasSriovVgpu || access(NOVA_GPU_CONF, F_OK) == 0) && !WriteNovaGpuConf()) {
        HexLogError("Failed to regenerate %s", NOVA_GPU_CONF);
    }

    return true;
}

CONFIG_MODULE(gpu, 0, 0, 0, 0, Commit);

CONFIG_MIGRATE(gpu, GPU_CONFIG_DIR);

CONFIG_COMMAND(gpu_resource_set, ResourceSetMain, ResourceSetUsage);
