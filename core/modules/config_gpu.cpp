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
        // The exit-code marker must be single-token to the shell: the '|'
        // characters are quoted so sh treats it as a literal echo argument,
        // not as pipes. Unquoted, "echo |__HEX_RC_$?__|" is a syntax error and
        // the whole line aborts before sriov-manage ever runs.
        const std::string output = HexUtilPOpen(
            "%s %s %s 2>&1; echo \"|__HEX_RC_$?__|\"", NVIDIA_SRIOV, op, sysfsAddr.c_str());

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

// Pulls one "Field Name : value" pair out of an `nvidia-smi -q` dump.
// Returns false when the field is absent or has no value, which every caller
// treats as "not confirmed" rather than as a default.
static bool
NvidiaSmiFieldValue(const std::string& output, const char* field, std::string* value)
{
    const size_t at = output.find(field);
    if (at == std::string::npos) {
        return false;
    }

    const size_t colon = output.find(':', at);
    if (colon == std::string::npos) {
        return false;
    }

    size_t eol = output.find('\n', colon);
    if (eol == std::string::npos) {
        eol = output.size();
    }

    const std::string raw = output.substr(colon + 1, eol - colon - 1);
    const size_t first = raw.find_first_not_of(" \t\r");
    if (first == std::string::npos) {
        return false;
    }
    const size_t last = raw.find_last_not_of(" \t\r");

    *value = raw.substr(first, last - first + 1);
    return true;
}

// Whether this card can host vGPUs of more than one framebuffer size at once.
// This is a static capability; the mode that uses it is not (see
// EnableHeterogeneousVgpuMode).
//
// Two spelling traps in one output: the capability is printed as
// "Heterogenous Multi-vGPU" - upstream is missing an 'e' - while the mode's
// state a few lines later is spelled "vGPU Heterogeneous Mode" correctly.
// The value is compared for equality rather than searched for, because the
// negative form is "Not Supported" and contains "Supported".
//
// An unreadable answer is a "no": the caller refuses a mixed-size request
// rather than reaching a mode switch that must fail after the card's previous
// carve has already been torn down.
static bool
HeterogeneousVgpuSupported(const std::string& gpuId)
{
    const std::string output = HexUtilPOpen("%s -q -i %s", NVIDIA_SMI, gpuId.c_str());

    std::string value;
    if (!NvidiaSmiFieldValue(output, "Heterogenous Multi-vGPU", &value)) {
        HexLogWarning("gpu_resource_set: could not read the heterogeneous vGPU capability of GPU %s; "
                      "treating it as unsupported", gpuId.c_str());
        return false;
    }

    return value == "Supported";
}

// Turns on the mode that lets one PF carry vGPUs of different framebuffer
// sizes. `nvidia-smi vgpu -shm` is the only interface - the PF has no
// nvidia/ sysfs directory, only its VFs do (cn13, 2026-08-21).
//
// The ordering this must be called in is not negotiable: after
// sriov-manage -e, before any current_vgpu_type write. The mode is *runtime*
// state and sriov-manage clears it in both directions, so setting it before
// the VFs are enabled is silently undone by the driver rebind - the mode reads
// Enabled beforehand and Disabled after, every VF's creatable_vgpu_types stays
// collapsed to one framebuffer size, and the cross-size write still fails.
// That failure is indistinguishable from "the hardware cannot do it".
//
// The same property is why there is no undo on teardown: releasing the VFs
// clears the mode by itself, so unlike MIG mode it can never outlive the carve
// it belongs to and no card is left in a mode nothing records.
//
// The exit code is trustworthy (rc=19 "In use by another client" when a vGPU
// already exists, rc=6 for an unknown -i), and the mode is read back anyway
// because a silent no-op is the one outcome this must not ship with. The state
// field reads N/A on a MIG-enabled card, which the equality check rejects.
static bool
EnableHeterogeneousVgpuMode(const std::string& gpuId)
{
    if (HexUtilSystemF(0, 0, "%s vgpu -shm 1 -i %s", NVIDIA_SMI, gpuId.c_str()) != 0) {
        HexLogError("gpu_resource_set: failed to enable heterogeneous vGPU mode on GPU %s",
                    gpuId.c_str());
        return false;
    }

    const std::string output = HexUtilPOpen("%s -q -i %s", NVIDIA_SMI, gpuId.c_str());

    std::string value;
    if (!NvidiaSmiFieldValue(output, "vGPU Heterogeneous Mode", &value) || value != "Enabled") {
        HexLogError("gpu_resource_set: heterogeneous vGPU mode did not take effect on GPU %s "
                    "(mode reads '%s')", gpuId.c_str(), value.c_str());
        return false;
    }

    return true;
}

// Enables the PF's VFs and writes each requested profile id into that many
// VFs' current_vgpu_type - the write is what actually carves the vGPU.
// profiles must already be validated. sriov-manage -e is idempotent for an
// already-enabled GPU (verified on cn13, 2026-07-17), so this is safe to
// re-run from boot-time Commit().
static bool
ApplySriovVgpu(const std::string& gpuId, const std::string& pciAddress,
               const json11::Json& profiles)
{
    const std::string sysfsAddr = SysfsPciAddr(pciAddress);

    if (!RunSriovManageWithRetry("-e", sysfsAddr)) {
        return false;
    }

    // Has to happen here: the VFs are up and nothing is carved yet. Cards that
    // do not advertise the capability are left alone - a request that actually
    // needs the mode is refused by ValidateVgpuProfiles long before this point,
    // so reaching here without it means a single-size carve, which behaves
    // identically either way (verified on cn13: same types, same placements,
    // same 32-vGPU ceiling with the mode on and off).
    if (HeterogeneousVgpuSupported(gpuId) && !EnableHeterogeneousVgpuMode(gpuId)) {
        TeardownSriov(sysfsAddr);
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
// already carries a vGPU type. Shared by sriovVgpu and migBackedVgpu - both
// end up in the same VF/current_vgpu_type sysfs shape once carved.
static bool
VfVgpuApplied(const std::string& sysfsAddr)
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

// A MIG-backed vGPU type as `nvidia-smi vgpu -s -v` reports it, keyed by its
// vGPU Type ID - what current_vgpu_type expects, and what migBackedVgpu profile
// ids now carry (gpu_vgpu_profile_list reports one entry per type rather than
// per GPU instance profile; see spec.md §5b).
//
// giProfileId is still needed because `mig -cgi` carves partitions by GPU
// Instance Profile ID, not by vGPU type. The mapping is only a function in this
// direction: a type belongs to exactly one GI profile, while one GI profile
// exposes many types (47 exposes 19 on cn13's RTX PRO 6000 Blackwell). Keying
// the other way round is what made the old list unable to express which
// framebuffer size or mode the operator asked for.
struct MigVgpuType {
    int typeId;
    std::string name;   // full name, for the Nova alias - same as the SR-IOV path
    int giProfileId;
    long fbMiB;         // this type's framebuffer; the grouping key for GI budgeting
    long perGi;         // Max Instances Per GI
    long maxInstances;  // how many of this type the whole card can host
};

// How many GPU instances of this type's profile the card allows, derived from
// the driver's own two numbers instead of parsing `mig -lgip` separately:
// Max Instances = Max Instances Per GI x GI Instances Total. Verified to hold
// for all 43 MIG-backed types on cn13 2026-08-04 (R6 in
// ../feat-905-mig-vgpu-infra/execution-log-cn13-mixed-fb.md).
static long
MigGiInstancesTotal(const MigVgpuType& type)
{
    return (type.perGi > 0) ? type.maxInstances / type.perGi : 0;
}

// Records a parsed block, but only once every field the apply and validation
// paths need is present. Anything incomplete is dropped rather than guessed at:
// SR-IOV time-sliced types share this output and legitimately lack a GPU
// instance profile, so "incomplete" is the normal case, not an error.
static void
AddMigVgpuType(std::map<int, MigVgpuType>& types, const MigVgpuType& type)
{
    if (type.typeId >= 0 && !type.name.empty() && type.giProfileId >= 0 &&
        type.fbMiB > 0 && type.perGi > 0 && type.maxInstances > 0) {
        types[type.typeId] = type;
    }
}

// Parses `nvidia-smi vgpu -s -v` output into a map of vGPU Type ID -> that
// type's MIG geometry. Blocks look like (mirroring ParseVgpuTypeNames, plus the
// fields only MIG-backed types populate):
//   vGPU Type ID                      : 0x619
//       Name                          : NVIDIA RTX Pro 6000 Blackwell DC-1-24Q
//       GPU Instance Profile ID       : 47
//       Max Instances Per VM          : 1
//       Max Instances Per GI          : 1
//       Max Instances                 : 4
//       FB Memory                     : 24576 MiB
static std::map<int, MigVgpuType>
ParseMigVgpuTypes(const std::string& smiOutput)
{
    std::map<int, MigVgpuType> types;
    std::istringstream stream(smiOutput);
    std::string line;

    MigVgpuType current = MigVgpuType { -1, "", -1, 0, 0, 0 };

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
            // A new block starts here, so the previous one is complete.
            AddMigVgpuType(types, current);
            current = MigVgpuType { (int)strtol(value.c_str(), NULL, 16), "", -1, 0, 0, 0 };
        } else if (key == "Name") {
            current.name = value;
        } else if (key == "GPU Instance Profile ID") {
            // Real hardware prints "N/A" here for SR-IOV time-sliced types: the
            // field is always present, contrary to the earlier assumption that
            // only MIG-backed types carried it (all 24 SR-IOV types on cn13
            // report N/A, 2026-08-04). strtol("N/A") is 0 and 0 is a real GI
            // profile id (MIG 4g.96gb), so accepting it fabricated a mapping
            // for a type with no partition behind it - and one that passed
            // validation, because 0 really is in the profile list. Leaving the
            // field unset instead makes AddMigVgpuType drop the whole block.
            if (!value.empty() && value.find_first_not_of("0123456789") == std::string::npos) {
                current.giProfileId = (int)strtol(value.c_str(), NULL, 10);
            }
        } else if (key == "Max Instances Per GI") {
            current.perGi = strtol(value.c_str(), NULL, 10);
        } else if (key == "Max Instances") {
            // Exact key match, so this cannot pick up "Max Instances Per VM" or
            // "Max Instances Per GI" - both contain this string.
            current.maxInstances = strtol(value.c_str(), NULL, 10);
        } else if (key == "FB Memory") {
            // "24576 MiB" - strtol stops at the space.
            current.fbMiB = strtol(value.c_str(), NULL, 10);
        }
    }

    AddMigVgpuType(types, current);

    return types;
}

// The GPU instances a migBackedVgpu request needs, keyed by
// (GPU Instance Profile ID, framebuffer size) -> how many instances of that
// partition shape have to exist.
//
// Both halves of the key matter, per the placement rules measured on cn13
// 2026-08-04 (R1-R4 in
// ../feat-905-mig-vgpu-infra/execution-log-cn13-mixed-fb.md): a GI only ever
// hosts one framebuffer size, though the Q/A/B/C mode may differ (DC-1-3Q and
// DC-1-3A coexisted in one GI, rc=0, while writing a 6144 MiB type into that
// same GI was refused); the same size may span several GIs; and a GI holds at
// most perGi of them. Two types can also share a framebuffer size while
// belonging to different GI profiles - 24576 MiB exists under profiles 47, 35
// and 32 on that card - and those are physically different partitions that
// cannot share one instance.
//
// So the instance count is per group: ceil(that group's total / perGi). Not one
// per requested vGPU (which over-carves whenever the type is smaller than its
// partition) and not one per profile (which under-carves past perGi).
static std::map<std::pair<int, long>, long>
BuildMigInstanceNeeds(const json11::Json& profiles, const std::map<int, MigVgpuType>& typesByTypeId)
{
    std::map<std::pair<int, long>, long> requested;  // group -> vGPUs asked for
    std::map<std::pair<int, long>, long> perGiOf;

    for (const json11::Json& profile : profiles.array_items()) {
        const std::map<int, MigVgpuType>::const_iterator typeIt =
            typesByTypeId.find((int)profile["id"].number_value());
        if (typeIt == typesByTypeId.end()) {
            // Callers reject unknown ids before planning; nothing to plan here.
            continue;
        }

        const std::pair<int, long> group(typeIt->second.giProfileId, typeIt->second.fbMiB);
        requested[group] += (long)profile["count"].number_value();
        // perGi is a property of the type, and every type in a group shares the
        // framebuffer size it is derived from, so any of them gives the same value.
        perGiOf[group] = typeIt->second.perGi;
    }

    std::map<std::pair<int, long>, long> needs;
    for (std::map<std::pair<int, long>, long>::const_iterator it = requested.begin();
         it != requested.end(); ++it) {
        // perGi is guaranteed positive: AddMigVgpuType drops types without it.
        const long perGi = perGiOf[it->first];
        needs[it->first] = (it->second + perGi - 1) / perGi;
    }

    return needs;
}

// Flattens BuildMigInstanceNeeds into one GPU Instance Profile ID per
// `mig -cgi` call to make.
static std::vector<int>
BuildMigInstancePlan(const json11::Json& profiles, const std::map<int, MigVgpuType>& typesByTypeId)
{
    const std::map<std::pair<int, long>, long> needs = BuildMigInstanceNeeds(profiles, typesByTypeId);

    std::vector<int> plan;
    for (std::map<std::pair<int, long>, long>::const_iterator it = needs.begin();
         it != needs.end(); ++it) {
        for (long i = 0; i < it->second; i++) {
            plan.push_back(it->first.first);
        }
    }

    return plan;
}

// Whether MIG mode is on right now, read before an apply enables it so a
// failed apply can put the card back the way it found it instead of forcing
// MIG off. Treats an unreadable answer as "already enabled", which is the
// conservative direction here: it makes the teardown leave MIG alone rather
// than turn off a mode this apply may not have been the one to enable.
static bool
MigModeEnabled(const std::string& gpuId)
{
    const std::string output = HexUtilPOpen(
        "%s --query-gpu=mig.mode.current --format=csv,noheader -i %s", NVIDIA_SMI, gpuId.c_str());

    return output.find("Disabled") == std::string::npos;
}

// Best-effort teardown after a failed MIG-backed apply: release the VFs
// (same as the SR-IOV path), destroy whatever GPU/compute instances this
// attempt created, then undo the MIG-mode enable if this attempt is what
// turned it on - so no half-configured GPU is left behind.
//
// sriov-manage -d rebinds the driver, which on its own already destroys
// every GPU instance on the card (confirmed on cn13 2026-08-04 - the same
// side effect that made the original apply ordering fail, see ApplyMigVgpu).
// The explicit -dci/-dgi calls that follow are therefore usually no-ops;
// they are kept as a safety net in case a driver version releases VFs
// without wiping instances. Releasing the consumers (VFs) before the
// resources (instances) is also the safer order - a VF holding a live vGPU
// backed by an instance can refuse that instance's destruction. Compute
// instances must be destroyed before their GPU instances.
//
// The MIG-mode undo is what keeps a failed apply recoverable. MIG mode is
// persistent state, and config.json only gains its migBackedVgpu entry after
// ApplyMigVgpu returns true - so on failure gpu_unset_current_type's
// `current_type = migBackedVgpu` branch, the only place that runs `-mig 0`,
// can never fire. Without this the card stays MIG-enabled with no product
// path back: a later switch to sriovVgpu writes a time-sliced type into a VF
// that cannot offer it and fails, exactly the dead end 48f96531 removed for
// the successful-apply case. It runs after TeardownSriov because the driver
// refuses `-mig 0` while VFs are enabled ("In use by another client",
// cn13 2026-08-04) - the same ordering that fix established.
//
// Only this attempt's own enable is undone. On the boot-time Commit()
// re-apply path MIG mode survived the reboot while the VFs and instances did
// not, so migWasEnabled is true there and a failed re-apply leaves the mode
// alone for the next Commit() to retry against.
static void
TeardownMigVgpu(const std::string& gpuId, const std::string& sysfsAddr, size_t createdInstances,
                bool migWasEnabled)
{
    TeardownSriov(sysfsAddr);

    if (createdInstances > 0) {
        HexUtilSystemF(0, 0, "%s mig -i %s -dci", NVIDIA_SMI, gpuId.c_str());
        HexUtilSystemF(0, 0, "%s mig -i %s -dgi", NVIDIA_SMI, gpuId.c_str());
    }

    if (!migWasEnabled) {
        HexUtilSystemF(0, 0, "%s -i %s -mig 0", NVIDIA_SMI, gpuId.c_str());
    }
}

// Enables MIG mode, enables the PF's VFs, carves one GPU+compute instance
// per requested profile (nvidia-smi mig -cgi <id> -C), then writes each
// instance's vGPU type into a VF's current_vgpu_type. profiles must already
// be validated (ids are GPU Instance Profile IDs).
//
// The VF step MUST come before instance creation. sriov-manage goes through
// the driver's unbindLock and rebinds the GPU, which wipes every GPU
// instance on the card - MIG mode itself is persistent state and survives,
// but the instances are runtime state and do not. Creating instances first
// (the original shape of this function, mirroring ApplySriovVgpu) left the
// card with zero instances by the time the VFs came up, so the driver had
// no MIG-backed vGPU type to offer: every VF's creatable_vgpu_types stayed
// empty and the current_vgpu_type write below failed with EIO
// (NVRM: Failed to add vgpu create request: 0x38). Verified on cn13
// 2026-08-04, both directions - see
// ../feat-905-mig-vgpu-infra/execution-log-cn13-vgpud-restart.md.
//
// Which instance each VF ends up serving is the driver's decision, not this
// function's: virtfnN/nvidia/gpu_instance_id and placement_id are outputs the
// driver fills in (they read ENXIO until a vGPU exists), so nothing here writes
// them. They are, however, trustworthy for reading the binding back - a VF's
// gpu_instance_id matched the instance actually carved in every case on cn13
// 2026-08-04, which also means the binding can be inspected without booting a
// VM. An earlier comment here claimed otherwise, on the strength of
// `nvidia-smi vgpu -q` reporting GPU Instance ID 3 for a vGPU whose Placement
// ID 6 "belongs to instance 5". That comparison was invalid: vgpu -q's
// Placement ID is the vGPU's offset *inside* its GI, while `mig -lgi`'s
// Placement Start is the GI's position on the card - two different coordinate
// systems, so the driver was never contradicting itself.
static bool
ApplyMigVgpu(const std::string& gpuId, const std::string& pciAddress, const json11::Json& profiles)
{
    const std::string sysfsAddr = SysfsPciAddr(pciAddress);

    // Everything that can fail without touching the card runs first, so a bad
    // request leaves no state behind at all. `vgpu -s -v` lists the statically
    // supported types and works with MIG mode still off (verified on cn13
    // 2026-08-04), so resolution does not need `-mig 1` to have run.
    const std::map<int, MigVgpuType> typesByTypeId =
        ParseMigVgpuTypes(HexUtilPOpen("%s vgpu -s -v -i %s", NVIDIA_SMI, gpuId.c_str()));

    // One entry per requested vGPU: these are the types written to the VFs.
    const std::vector<int> vgpuTypePlan = BuildVfAssignmentPlan(profiles);

    for (size_t i = 0; i < vgpuTypePlan.size(); i++) {
        if (typesByTypeId.find(vgpuTypePlan[i]) == typesByTypeId.end()) {
            HexLogError("gpu_resource_set: vGPU type %d is not a MIG-backed type on GPU %s",
                        vgpuTypePlan[i], gpuId.c_str());
            return false;
        }
    }

    // The partitions those vGPUs need - far fewer than one per vGPU whenever the
    // chosen type is smaller than the partition it lives in.
    const std::vector<int> giProfilePlan = BuildMigInstancePlan(profiles, typesByTypeId);
    if (giProfilePlan.empty()) {
        HexLogError("gpu_resource_set: could not plan any GPU instance for the request on GPU %s",
                    gpuId.c_str());
        return false;
    }

    // Sampled before the enable below so the teardown can tell this attempt's
    // own MIG-mode change apart from one that was already in place.
    const bool migWasEnabled = MigModeEnabled(gpuId);

    if (HexUtilSystemF(0, 0, "%s -i %s -mig 1", NVIDIA_SMI, gpuId.c_str()) != 0) {
        HexLogError("gpu_resource_set: failed to enable MIG mode on GPU %s", gpuId.c_str());
        return false;
    }

    // Every failure from here on has to go through the teardown: MIG mode is
    // now on, and if it stays on with no config.json entry recording it the
    // card has no product path back to another resource type.
    if (!RunSriovManageWithRetry("-e", sysfsAddr)) {
        TeardownMigVgpu(gpuId, sysfsAddr, 0, migWasEnabled);
        return false;
    }

    size_t created = 0;
    for (; created < giProfilePlan.size(); created++) {
        if (HexUtilSystemF(0, 0, "%s mig -i %s -cgi %d -C", NVIDIA_SMI, gpuId.c_str(), giProfilePlan[created]) != 0) {
            HexLogError("gpu_resource_set: failed to create a GPU instance (profile %d) on GPU %s",
                        giProfilePlan[created], gpuId.c_str());
            TeardownMigVgpu(gpuId, sysfsAddr, created, migWasEnabled);
            return false;
        }
    }

    for (size_t vf = 0; vf < vgpuTypePlan.size(); vf++) {
        const std::string typePath = std::string(PCI_DEVICES_DIR) + "/" + sysfsAddr +
            "/virtfn" + std::to_string(vf) + "/nvidia/current_vgpu_type";

        if (!WriteSysfs(typePath, std::to_string(vgpuTypePlan[vf]))) {
            HexLogError("gpu_resource_set: failed to set MIG-backed vGPU type %d on %s/virtfn%d",
                        vgpuTypePlan[vf], sysfsAddr.c_str(), (int)vf);
            TeardownMigVgpu(gpuId, sysfsAddr, created, migWasEnabled);
            return false;
        }
    }

    return true;
}

// A passthrough-eligible VF, regardless of which vGPU flavor (SR-IOV
// time-sliced or MIG-backed) it was carved for - Nova only cares that it's
// a type-VF PCI device, not how its vGPU type was assigned.
struct PciVf {
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
GetPciVfs(const std::string& sysfsAddr, size_t count, std::vector<PciVf>* vfs)
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

        PciVf vf;
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

// A truth-file entry is backed by a passthrough VF - and therefore belongs
// in the Nova drop-in - regardless of whether its vGPU type came from
// SR-IOV time-slicing or a MIG GPU instance.
static bool
IsVfBackedType(const json11::Json& type)
{
    return type.is_string() && (type.string_value() == "sriovVgpu" || type.string_value() == "migBackedVgpu");
}

// Builds the /etc/nova/nova.d/gpu.conf content from config.json entries:
// one [pci] alias per profile and one passthrough_whitelist per assigned VF
// of every sriovVgpu/migBackedVgpu GPU. Regenerating everything from the
// truth file means entries for GPUs switched away from either type
// disappear without any dedicated cleanup logic.
static std::string
BuildNovaGpuConfContent(const json11::Json& gpuConfig,
                        const std::map<std::string, std::vector<PciVf>>& vfsByGpuId)
{
    std::string content =
        "# Generated by hex_config (gpu_resource_set / gpu Commit). Do not edit.\n"
        "[pci]\n";

    for (const json11::Json& entry : gpuConfig.array_items()) {
        if (!IsVfBackedType(entry["type"])) {
            continue;
        }

        const std::map<std::string, std::vector<PciVf>>::const_iterator vfsIt =
            vfsByGpuId.find(entry["id"].string_value());
        if (vfsIt == vfsByGpuId.end() || vfsIt->second.empty()) {
            continue;
        }

        const std::vector<PciVf>& vfs = vfsIt->second;

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

    std::map<std::string, std::vector<PciVf>> vfsByGpuId;

    for (const json11::Json& entry : gpuConfig.array_items()) {
        if (!IsVfBackedType(entry["type"])) {
            continue;
        }

        const std::string gpuId = entry["id"].string_value();
        const std::string type = entry["type"].string_value();

        if (!entry["pciAddress"].is_string() || entry["pciAddress"].string_value().empty()) {
            HexLogError("GPU %s has type %s but no recorded pciAddress", gpuId.c_str(), type.c_str());
            return false;
        }

        size_t assigned = 0;
        for (const json11::Json& profile : entry["profiles"].array_items()) {
            assigned += (size_t)profile["count"].number_value();
        }

        std::vector<PciVf> vfs;
        if (!GetPciVfs(SysfsPciAddr(entry["pciAddress"].string_value()), assigned, &vfs)) {
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

// Total device framebuffer, for the MIG capacity check below. Returns 0 when
// nvidia-smi reports nothing parseable; the caller treats that as a failed
// check rather than an unlimited budget.
static long
GetGpuTotalVramMiB(const char* gpuId)
{
    const std::string output = HexUtilPOpen(
        "%s --query-gpu=memory.total --format=csv,noheader,nounits -i %s", NVIDIA_SMI, gpuId);
    return strtol(output.c_str(), NULL, 10);
}

// Validates the profiles argument for sriovVgpu/migBackedVgpu:
// - format: a non-empty JSON array of { id, count } objects with unique
//   non-negative-integer ids and positive-integer counts
// - existence: every id must be an available profile of the requested type
//   on this GPU, as reported by gpu_vgpu_profile_list
// - heterogeneity (SR-IOV): a request spanning more than one framebuffer size
//   needs the card's heterogeneous vGPU mode, so the card has to advertise the
//   capability. Checked here rather than left to apply time because
//   gpu_unset_current_type has already destroyed the previous carve by then -
//   an apply-time rejection costs the card its working configuration. It runs
//   ahead of the capacity rule below because it reads nothing from sysfs: a
//   card that cannot serve the request at all should say so by name even on a
//   node where sriov_totalvfs happens to be unreadable.
// - capacity (SR-IOV): each vGPU instance occupies one VF, so the total
//   requested count must fit within the PF's sriov_totalvfs
// - capacity (MIG-backed), three rules:
//     1. each type's requested count must fit within its own vmCountLimit
//        (Max Instances - how many of that type the whole card can host)
//     2. the combined vramMiB*count of the request must fit within the
//        device's total framebuffer
//     3. the GPU instances the request needs must fit within the number the
//        card can create. Rules 1 and 2 can both pass on a request the driver
//        then refuses: one vGPU each of five different memory sizes on cn13
//        uses a quarter of the card's memory, yet needs five partitions where
//        only four exist. See BuildMigInstanceNeeds and spec.md §5c.
//   Rule 3 does not model cross-profile slice coupling (R7: 1g/2g/4g partitions
//   draw on one shared pool, so mixing partition *shapes* can run out of slices
//   even when each shape's own instance count is fine). nvidia-smi mig -cgi
//   enforces that at apply time and ApplyMigVgpu is fail-fast. The SR-IOV
//   framebuffer-size restriction started out the same way and has since been
//   promoted to a pre-check (the heterogeneity rule above), for the reason
//   given there: by apply time the previous carve is already gone.
//
// migTypes is the parsed `nvidia-smi vgpu -s -v` geometry, supplied by the
// caller so the same output serves validation and persistence; it is empty for
// non-MIG requests. Rule 3 needs the driver's own Max Instances Per GI rather
// than a memory division: a 1g.24gb partition reports 23.12 GiB usable but the
// driver budgets vGPUs against the profile's nominal 24576 MiB, so eight
// 3072 MiB vGPUs fit where 23674/3072 would have allowed only seven (cn13 R4).
static bool
ValidateVgpuProfiles(const char* gpuId, const char* newType, const char* profiles,
                     const std::string& pciAddress, const std::map<int, MigVgpuType>& migTypes)
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

    if (strcmp(newType, "sriovVgpu") == 0) {
        // Not gated on pciAddress: this rule is about the card's advertised
        // capability, which nvidia-smi answers by UUID.
        std::map<int, double> sriovVramMiBById;

        for (const json11::Json& profile : profileList[listKey].array_items()) {
            if (profile["id"].is_number()) {
                sriovVramMiBById[(int)profile["id"].number_value()] =
                    profile["vramMiB"].number_value();
            }
        }

        std::set<double> requestedSizes;

        for (const int id : requestedIds) {
            const std::map<int, double>::const_iterator it = sriovVramMiBById.find(id);

            // Fails closed: without every requested profile's framebuffer size
            // there is no way to tell whether the request mixes sizes, and
            // guessing "it doesn't" is the direction that reaches the card.
            if (it == sriovVramMiBById.end() || it->second <= 0) {
                HexLogError("gpu_resource_set: could not read the framebuffer size of profile %d "
                            "on GPU %s; cannot tell whether the request mixes sizes", id, gpuId);
                return false;
            }

            requestedSizes.insert(it->second);
        }

        if (requestedSizes.size() > 1 && !HeterogeneousVgpuSupported(gpuId)) {
            HexLogError("gpu_resource_set: the request mixes %zu vGPU framebuffer sizes, but GPU %s "
                        "does not report 'Heterogenous Multi-vGPU : Supported'; a single-size "
                        "request is required on this card",
                        requestedSizes.size(), gpuId);
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

    if (strcmp(newType, "migBackedVgpu") == 0) {
        std::map<int, double> vramMiBById;
        std::map<int, long> vmCountLimitById;

        for (const json11::Json& profile : profileList[listKey].array_items()) {
            if (!profile["id"].is_number()) {
                continue;
            }
            const int id = (int)profile["id"].number_value();
            vramMiBById[id] = profile["vramMiB"].number_value();
            vmCountLimitById[id] = profile["vmCountLimit"].is_number() ?
                (long)profile["vmCountLimit"].number_value() : -1;
        }

        double requestedVramMiB = 0;

        for (const json11::Json& profile : parsed.array_items()) {
            const int id = (int)profile["id"].number_value();
            const long count = (long)profile["count"].number_value();

            const std::map<int, long>::const_iterator limitIt = vmCountLimitById.find(id);
            if (limitIt != vmCountLimitById.end() && limitIt->second >= 0 && count > limitIt->second) {
                HexLogError("gpu_resource_set: requested %ld instance(s) of profile %d exceeds the %ld "
                            "instance(s) available on GPU %s", count, id, limitIt->second, gpuId);
                return false;
            }

            requestedVramMiB += vramMiBById[id] * count;
        }

        // Rule 2 fails closed for the same reason rule 3 below does: an
        // unreadable budget is not a confirmation that the request fits, and
        // skipping the rule lets the request reach ApplyMigVgpu and mutate the
        // card before anything notices. This is the shape PR #1141 flagged as a
        // silent bypass of capacity validation on the SR-IOV check above, fixed
        // there in 79734b07 - the MIG rules follow the same contract.
        const long totalVramMiB = GetGpuTotalVramMiB(gpuId);
        if (totalVramMiB <= 0) {
            HexLogError("gpu_resource_set: could not read the total framebuffer of GPU %s; "
                        "cannot verify the request fits", gpuId);
            return false;
        }

        if (requestedVramMiB > totalVramMiB) {
            HexLogError("gpu_resource_set: requested %.0f MiB of MIG-backed vGPU memory exceeds the %ld MiB "
                        "available on GPU %s", requestedVramMiB, totalVramMiB, gpuId);
            return false;
        }

        // Rule 3 needs the driver's partition geometry. Refuse rather than skip
        // the rule if it is unavailable: a request that reaches ApplyMigVgpu
        // unchecked mutates the card before failing.
        if (migTypes.empty()) {
            HexLogError("gpu_resource_set: could not read the MIG-backed vGPU types of GPU %s; "
                        "cannot verify the request fits", gpuId);
            return false;
        }

        for (const int id : requestedIds) {
            if (migTypes.find(id) == migTypes.end()) {
                HexLogError("gpu_resource_set: vGPU type %d is not a MIG-backed type on GPU %s", id, gpuId);
                return false;
            }
        }

        // Each distinct (partition shape, vGPU memory size) pair needs its own
        // GPU instances; sum them per profile and compare with what the card can
        // create. Grouped this way so the two ways of getting it wrong are both
        // excluded: one instance per requested vGPU over-carves, one per
        // selected type under-carves past Max Instances Per GI.
        std::map<int, long> neededByGiProfile;
        const std::map<std::pair<int, long>, long> needs = BuildMigInstanceNeeds(parsed, migTypes);
        for (std::map<std::pair<int, long>, long>::const_iterator it = needs.begin();
             it != needs.end(); ++it) {
            neededByGiProfile[it->first.first] += it->second;
        }

        for (std::map<int, long>::const_iterator it = neededByGiProfile.begin();
             it != neededByGiProfile.end(); ++it) {
            long available = 0;
            for (std::map<int, MigVgpuType>::const_iterator typeIt = migTypes.begin();
                 typeIt != migTypes.end(); ++typeIt) {
                if (typeIt->second.giProfileId == it->first) {
                    available = MigGiInstancesTotal(typeIt->second);
                    break;
                }
            }

            // Max Instances = Max Instances Per GI x GI Instances Total, so this
            // is positive for every type the driver reports (verified for all 43
            // MIG-backed types on cn13 2026-08-04, R6). A zero here means that
            // invariant did not hold, which is exactly when the budget must not
            // be assumed sufficient.
            if (available <= 0) {
                HexLogError("gpu_resource_set: could not determine how many GPU instance(s) of profile %d "
                            "GPU %s allows; cannot verify the request fits", it->first, gpuId);
                return false;
            }

            if (it->second > available) {
                HexLogError("gpu_resource_set: the request needs %ld GPU instance(s) of profile %d on GPU %s "
                            "but only %ld can exist; every distinct vGPU memory size needs its own instance, "
                            "so select fewer sizes or fewer of the larger ones",
                            it->second, it->first, gpuId, available);
                return false;
            }
        }
    }

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

    // Read the device up front: releasing a pgpu from vfio-pci below has to
    // happen before the pre-condition check, so name/pciAddress/type are
    // needed earlier than the binding and persisting steps that follow.
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

    const std::string currentType = device["type"].is_string() ? device["type"].string_value() : "";

    // A pgpu is bound to vfio-pci, which makes it invisible to nvidia-smi -
    // and both checks below read the card's supported vGPU types through
    // nvidia-smi, so on a pgpu they would reject every profile as unsupported.
    // Hand the card back to its native driver first, and re-bind it if the
    // checks fail, so a rejected request still leaves it exactly as it was.
    const bool releasedFromVfio = (currentType == "pgpu" && strcmp(newType, "pgpu") != 0);
    if (releasedFromVfio &&
        HexUtilSystemF(0, 0, HEX_SDK " gpu_unbind_vfio_pci %s", pciAddress.c_str()) != 0) {
        HexLogError("gpu_resource_set: failed to release GPU %s from vfio-pci for validation", gpuId);
        return EXIT_FAILURE;
    }

    // Read once here rather than inside each consumer: the same `vgpu -s -v`
    // output drives the capacity check's GPU-instance rule and the name/alias
    // enrichment further down. It has to come after the vfio-pci release above,
    // since a pgpu is invisible to nvidia-smi while bound to vfio-pci.
    const std::map<int, MigVgpuType> migTypes =
        (strcmp(newType, "migBackedVgpu") == 0)
            ? ParseMigVgpuTypes(HexUtilPOpen("%s vgpu -s -v -i %s", NVIDIA_SMI, gpuId))
            : std::map<int, MigVgpuType>();

    // Both checks run before gpu_unset_current_type below so that a bad
    // request cannot tear down the GPU's existing configuration.
    const bool preChecksPassed =
        HexUtilSystemF(0, 0, HEX_SDK " gpu_resource_set_check %s %s %s", gpuId, newType, profiles) == 0 &&
        (strcmp(newType, "pgpu") == 0 ||
         ValidateVgpuProfiles(gpuId, newType, profiles, pciAddress, migTypes));

    if (!preChecksPassed) {
        HexLogError("gpu_resource_set: pre-condition check failed for GPU %s", gpuId);

        if (releasedFromVfio &&
            HexUtilSystemF(0, 0, HEX_SDK " gpu_bind_vfio_pci %s", pciAddress.c_str()) != 0) {
            HexLogError("gpu_resource_set: GPU %s also failed to re-bind to vfio-pci; it is left out of passthrough despite still being recorded as pgpu", gpuId);
        }

        return EXIT_FAILURE;
    }

    if (HexUtilSystemF(0, 0, HEX_SDK " gpu_unset_current_type %s", gpuId) != 0) {
        HexLogError("gpu_resource_set: failed to unset current type for GPU %s", gpuId);

        // Same rollback as the failed-checks path above: the card is still
        // recorded as pgpu, so put it back into passthrough rather than
        // leaving the record and the hardware disagreeing.
        if (releasedFromVfio &&
            HexUtilSystemF(0, 0, HEX_SDK " gpu_bind_vfio_pci %s", pciAddress.c_str()) != 0) {
            HexLogError("gpu_resource_set: GPU %s also failed to re-bind to vfio-pci; it is left out of passthrough despite still being recorded as pgpu", gpuId);
        }

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

        if (!ApplySriovVgpu(gpuId, pciAddress, requested)) {
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
        // Existence of every requested id (a vGPU Type ID) was confirmed by
        // ValidateVgpuProfiles above; parse cannot fail here.
        std::string jsonError;
        const json11::Json requested = json11::Json::parse(profiles, jsonError);

        // Enrich the requested {id, count} pairs with name/alias for
        // persistence (#894 schema: {id, name, count, alias}). id is the vGPU
        // Type ID throughout, the same as the SR-IOV path - so both vGPU
        // flavours now derive their Nova alias from the same kind of id, and
        // count means the same thing in both (vGPUs, not partitions). The GPU
        // Instance Profile ID each type needs stays internal to ApplyMigVgpu.
        json11::Json::array persistedProfiles;
        for (const json11::Json& profile : requested.array_items()) {
            const int id = (int)profile["id"].number_value();

            const std::map<int, MigVgpuType>::const_iterator typeIt = migTypes.find(id);
            if (typeIt == migTypes.end()) {
                HexLogError("gpu_resource_set: failed to resolve MIG-backed vGPU type %d on GPU %s",
                            id, gpuId);
                return EXIT_FAILURE;
            }

            persistedProfiles.push_back(json11::Json::object {
                { "id", id },
                { "name", typeIt->second.name },
                { "count", (int)profile["count"].number_value() },
                { "alias", ProfileAlias(typeIt->second.name, id) },
            });
        }

        if (!ApplyMigVgpu(gpuId, pciAddress, requested)) {
            HexLogError("gpu_resource_set: failed to apply MIG-backed vGPU partitioning on GPU %s", gpuId);
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
                "'map(select(.id != $id)) + [{id:$id, name:$name, type:\"migBackedVgpu\", pciAddress:$pciAddress, profiles:$profiles}]' %s > %s",
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

        HexLogInfo("gpu_resource_set: successfully updated GPU %s to migBackedVgpu", gpuId);
        return EXIT_SUCCESS;
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

    bool hasVfBackedVgpu = false;

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
        } else if (type == "sriovVgpu" || type == "migBackedVgpu") {
            // GPU is optional hardware: a single card's sysfs state being
            // unreadable or an apply hiccup should not fail Commit() for
            // the whole node and force a reboot. Log and move on to the
            // next entry instead.
            if (!entry["pciAddress"].is_string() || entry["pciAddress"].string_value().empty()) {
                HexLogError("GPU %s has type %s but no recorded pciAddress; cannot re-apply partitioning",
                            id.c_str(), type.c_str());
                continue;
            }

            const std::string pciAddress = entry["pciAddress"].string_value();

            // VF enablement, GPU/compute instances (MIG-backed only), and
            // per-VF vGPU types are runtime state and do not survive a
            // reboot. Skip GPUs that still carry an applied layout - this
            // also keeps runtime commits from disturbing vGPUs attached to
            // running VMs.
            if (!VfVgpuApplied(SysfsPciAddr(pciAddress))) {
                const bool applied = (type == "sriovVgpu")
                    ? ApplySriovVgpu(id, pciAddress, entry["profiles"])
                    : ApplyMigVgpu(id, pciAddress, entry["profiles"]);

                if (!applied) {
                    HexLogError("Failed to re-apply %s partitioning for GPU %s", type.c_str(), id.c_str());
                    continue;
                }
            }

            hasVfBackedVgpu = true;
        }
    }

    // The drop-in's content derives solely from config.json, which does not
    // change across reboots, so no nova restart is needed here -
    // regeneration is self-healing only (e.g. after a lost/stale gpu.conf).
    // Also regenerate when a drop-in exists but no sriovVgpu/migBackedVgpu
    // entry remains, so entries of cards switched away from either don't
    // linger.
    //
    // A regen failure here means Nova's GPU scheduling info may be stale,
    // not that the node's policy apply should fail and force a reboot.
    if ((hasVfBackedVgpu || access(NOVA_GPU_CONF, F_OK) == 0) && !WriteNovaGpuConf()) {
        HexLogError("Failed to regenerate %s", NOVA_GPU_CONF);
    }

    return true;
}

CONFIG_MODULE(gpu, 0, 0, 0, 0, Commit);

CONFIG_MIGRATE(gpu, GPU_CONFIG_DIR);

CONFIG_COMMAND(gpu_resource_set, ResourceSetMain, ResourceSetUsage);
