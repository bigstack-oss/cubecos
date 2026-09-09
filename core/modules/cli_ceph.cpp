// CUBE SDK

#include <algorithm>
#include <cube/cubesys.h>
#include <hex/cli_module.h>
#include <hex/cli_util.h>
#include <hex/exec.hpp>
#include <hex/log.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/strict.h>
#include <hex/string_util.h>
#include <hex/yml_util.h>
#include <netinet/in.h>
#include <string>
#include <sys/socket.h>
#include <unistd.h>
#include <vector>

#define DISK_H_FMT " %6s  %12s  %8s  %8s  %8s  %18s\n--\n"
#define DISK_FMT " %6u  %12s  %8s  %8s  %8s  %18s\n"
#define DISK_F_FMT "--\n"
#define OSD_H_FMT " %6s  %12s  %8s  %6s  %18s\n--\n"
#define OSD_FMT " %6lu  %12s  %8s  %6s  %18s\n"
#define OSD_F_FMT "--\n"
#define LIST_OSD_FMT "%8s %8s %16s %10s %18s %10s %6s %s\n"

static const char* LABEL_SITE_IP = "Enter IP address (required): ";
static const char* LABEL_SITE_SECRET = "Enter remote secret (required): ";

const std::string BUILTIN_BACKPOOL = "cinder-volumes";

static int CephListOsdMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="list_osd" [1]="[<osd_id>]" */) {
        return CLI_INVALID_ARGS;
    }

    std::string osdId;
    if (argc == 2) {
        osdId = argv[1];
        HexSystemF(0, "hex_sdk cmd -v \"hex_sdk -v ceph_osd_list %s\" | cut -d'|' -f3", osdId.c_str());
    } else {
        printf(LIST_OSD_FMT, "OSD", "STATE", "HOST", "DEV", "SERIAL", "POWER_ON", "USE", "REMARK");
        HexSystemF(0, "hex_sdk cmd -v hex_sdk ceph_osd_list | cut -d'|' -f3 | sort -k3");
    }
    return CLI_SUCCESS;
}

static int CephShowCache(int argc, const char** argv)
{
    if (argc > 2 /* [0]="status"  [1]="backpool" */) {
        HexSystemF(0, HEX_SDK " -v ceph_backpool_cache_list");
        return CLI_INVALID_ARGS;
    }

    std::string backPool;
    if (argc == 2) {
        backPool = argv[1];
    } else {
        int index;
        std::string optCmd = std::string(HEX_SDK) + " ceph_backpool_cache_list";
        std::string descCmd = std::string(HEX_SDK) + " -v ceph_backpool_cache_list";
        if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &backPool, "Enter index of back pool to check its cache status: ") != CLI_SUCCESS) {
            CliPrintf("No cache tier available or invalid index chosen");
            return CLI_SUCCESS;
        }
    }

    // handle one liner case when backPool does not exist. ex: status nosuchpool
    std::string validBackPool = HexUtilPOpen(HEX_SDK " ceph_get_pool_in_cacheable_backpool %s", backPool.c_str());
    if (validBackPool.empty()) {
        CliPrintf("Pool %s either does not support cache tiering or does not exist", backPool.c_str());
        return CLI_UNEXPECTED_ERROR;
    }

    std::string cachePool = HexUtilPOpen(HEX_SDK " ceph_get_cache_by_backpool %s", backPool.c_str());
    if (cachePool.empty()) {
        CliPrintf("Failed to find cache associated with backpool: %s", backPool.c_str());
    } else {
        CliPrintf("%s/%s", backPool.c_str(), cachePool.c_str());

        std::string onOffMsgs = HexUtilPOpen(HEX_SDK " ceph_osd_test_cache %s", backPool.c_str());
        CliPrintf("Status: %s", onOffMsgs.c_str());

        std::string profile = HexUtilPOpen(HEX_SDK " ceph_osd_cache_profile_get %s", backPool.c_str());
        CliPrintf("Profile: %s", profile.c_str());
        // when cache is off, return directly
        if (onOffMsgs == "off")
            return CLI_SUCCESS;
        std::string statMsgs = HexUtilPOpen("timeout 10 ceph df | grep %s | awk {'print $7 $8\"\t\"$10 $11'}", cachePool.c_str());
        size_t len = statMsgs.size();
        if (len > 0 && statMsgs[len - 1] == '\n')
            statMsgs[len - 1] = '\0';
        CliPrintf("USED\tFREE\n--");
        CliPrintf("%s", statMsgs.c_str());
        CliPrintf("--");
    }

    return CLI_SUCCESS;
}

static int CephSwitchCache(int argc, const char** argv)
{
    if (argc > 3 /* [0]="switch" [1]="backpool" [2]="<[on|off]>" */) {
        HexSystemF(0, HEX_SDK " -v ceph_cacheable_backpool_list");
        return CLI_INVALID_ARGS;
    }

    std::string backPool;
    std::string input;
    if (argc == 3) {
        backPool = argv[1];
        input = argv[2];
    } else if (argc == 2) {
        backPool = argv[1];
    } else {
        int index;
        std::string optCmd = std::string(HEX_SDK) + " ceph_cacheable_backpool_list";
        std::string descCmd = std::string(HEX_SDK) + " -v ceph_cacheable_backpool_list";
        if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &backPool, "Enter index of back pool to create cache for: ") != CLI_SUCCESS) {
            CliPrintf("No cache tier available or invalid index chosen");
            return CLI_SUCCESS;
        }
    }

    // handle one liner case when backPool does not exist. ex: switch nosuchpool on
    std::string validBackPool = HexUtilPOpen(HEX_SDK " ceph_get_pool_in_cacheable_backpool %s", backPool.c_str());
    if (validBackPool.empty()) {
        CliPrintf("Pool %s either does not support cache tiering or does not exist", backPool.c_str());
        return CLI_UNEXPECTED_ERROR;
    }

    std::string cachePool = HexUtilPOpen(HEX_SDK " ceph_get_cache_by_backpool %s", backPool.c_str());
    if (cachePool.empty()) {
        CliPrintf("Create a new cachepool for backpool: %s", backPool.c_str());
        if (!CliReadConfirmation())
            return CLI_SUCCESS;

        cachePool = HexUtilPOpen(HEX_SDK " ceph_create_cachepool %s", backPool.c_str());
    }
    std::string onOffMsgs = HexUtilPOpen(HEX_SDK " ceph_osd_test_cache %s", backPool.c_str());
    if (input.empty()) {
        CliPrintf("Current %s/%s status: %s", backPool.c_str(), cachePool.c_str(), onOffMsgs.c_str());
        CliReadLine("Turn cache (on/off): ", input);
    }

    int ret = 0;
    if (onOffMsgs == input) {
        CliPrintf("No operation performed because cache is already %s.", input.c_str());
    } else if (input == "on") {
        if ((ret = HexUtilSystemF(0, 0, HEX_SDK " ceph_osd_create_cache %s", backPool.c_str()))) {
            CliPrintf("Failed to switch on cache for backpool: %s", backPool.c_str());
        }
    } else if (input == "off") {
        if ((ret = HexUtilSystemF(0, 0, HEX_SDK " ceph_osd_disable_cache %s", backPool.c_str()))) {
            CliPrintf("Failed to switch off cache for backpool: %s", backPool.c_str());
        }
    } else {
        CliPrintf("No operation performed.");
    }
    return CLI_SUCCESS;
}

static int CephCacheProfileSet(int argc, const char** argv)
{
    if (argc > 3 /* [0]="set_profile" [1]="backpool" [2]="<[high-burst|default|low-burst]>" */) {
        HexSystemF(0, HEX_SDK " -v ceph_backpool_cache_list");
        return CLI_INVALID_ARGS;
    }

    std::string backPool;
    std::string profile;
    if (argc == 3) {
        backPool = argv[1];
        profile = argv[2];
    } else if (argc == 2) {
        backPool = argv[1];
    } else {
        int index;
        std::string optCmd = std::string(HEX_SDK) + " ceph_backpool_cache_list";
        std::string descCmd = std::string(HEX_SDK) + " -v ceph_backpool_cache_list";
        if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &backPool, "Enter index of back pool to set cache profile: ") != CLI_SUCCESS) {
            CliPrintf("No cache tier available or invalid index chosen");
            return CLI_SUCCESS;
        }
    }

    // handle one liner case when backPool does not exist. ex: set_profile nosuchpool high-burst
    std::string validBackPool = HexUtilPOpen(HEX_SDK " ceph_get_pool_in_cacheable_backpool %s", backPool.c_str());
    if (validBackPool.empty()) {
        CliPrintf("Pool %s either does not support cache tiering or does not exist", backPool.c_str());
        return CLI_UNEXPECTED_ERROR;
    }

    std::string cachePool = HexUtilPOpen(HEX_SDK " ceph_get_cache_by_backpool %s", backPool.c_str());
    if (cachePool.empty()) {
        CliPrintf("Failed to find cache associated with backpool: %s", backPool.c_str());
    } else if (profile.empty()) {
        int index;
        std::string cmd = "echo 'high-burst\ndefault\nlow-burst'";
        std::string desc = "echo 'high-burst (70% burst, 30% cache)\ndefault (40% burst, 60% cache)\nlow-burst (20% burst, 80% cache)'";
        if (CliMatchCmdDescHelper(argc, argv, 2, cmd, desc, &index, &profile, "Select profile: ") != CLI_SUCCESS) {
            CliPrintf("Invalid profile");
            return CLI_INVALID_ARGS;
        }
    }

    if (HexSpawn(0, HEX_SDK, "ceph_osd_cache_profile_set", backPool.c_str(), profile.c_str(), NULL) == 0)
        CliPrintf("Cache profile '%s/%s %s' configured", backPool.c_str(), cachePool.c_str(), profile.c_str());

    return CLI_SUCCESS;
}

static int CephPromoteDiskToCache(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    // 0. List all active OSDs
    // Note: only bluestore OSDs can be promoted
    std::string osddev = HexUtilPOpen(HEX_SDK " ceph_osd_list_disk");

    // 1. Filter-out those disks already promoted
    std::vector<std::string> allDevs = hex_string_util::split(osddev, ' ');
    std::vector<std::string> matchedDevs;
    for (auto& d : allDevs) {
        // only proceed for valid scsi disk (e.g.: /dev/sdc)
        if (d.length() < 8)
            continue;
        std::string typ = HexUtilPOpen(HEX_SDK " ceph_osd_get_class %s", d.c_str());
        // display only non ssd device (e.g.: hdd or nvme)
        if (typ == "ssd")
            continue;
        matchedDevs.push_back(d);
    }
    // 1.a) return directly if no avail disk
    size_t cnt = matchedDevs.size();
    if (!cnt) {
        CliPrintf("No available disk.");
        return CLI_SUCCESS;
    }
    // 1.b) display candidates
    printf(OSD_H_FMT, "index", "name", "size", "osd", "serial");
    for (size_t i = 0; i < cnt; i++) {
        std::string sz = HexUtilPOpen("echo -n $(lsblk -n -d -o SIZE %s)", matchedDevs[i].c_str());
        std::string ids = HexUtilPOpen(HEX_SDK " ceph_get_ids_by_dev %s", matchedDevs[i].c_str());
        std::string sn = HexUtilPOpen(HEX_SDK " ceph_get_sn_by_dev %s", matchedDevs[i].c_str());
        printf(OSD_FMT, i + 1, matchedDevs[i].c_str(), sz.c_str(), ids.c_str(), sn.c_str());
    }
    printf(OSD_F_FMT);

    // 2. User input
    std::string input;
    size_t index = 0;
    CliReadLine("Enter the index to promote: ", input);
    if (!HexParseUInt(input.c_str(), 1, cnt, &index)) {
        CliPrintf("Invalid index, cancelled.");
        return CLI_SUCCESS;
    }
    // 3. Promote disk
    if (HexUtilSystemF(0, 0, HEX_SDK " ceph_osd_promote_disk %s", matchedDevs[index - 1].c_str())) {
        return CLI_SUCCESS;
    }

    return CLI_SUCCESS;
}

static int CephDemoteDiskToCache(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    // 1. List all candidate OSDs and display to user
    std::string osddev = HexUtilPOpen(HEX_SDK " ceph_osd_list_disk");
    std::vector<std::string> allDevs = hex_string_util::split(osddev, ' ');
    std::vector<std::string> matchedDevs;
    for (auto& d : allDevs) {
        // only proceed for valid scsi disk (e.g.: /dev/sdc)
        if (d.length() < 8)
            continue;
        std::string typ = HexUtilPOpen(HEX_SDK " ceph_osd_get_class %s", d.c_str());
        // display only ssd device
        if (typ != "ssd")
            continue;
        matchedDevs.push_back(d);
    }
    // 1.a) return directly if no avail disk
    size_t cnt = matchedDevs.size();
    if (!cnt) {
        CliPrintf("No available disk.");
        return CLI_SUCCESS;
    }
    // 1.b) display candidates
    printf(OSD_H_FMT, "index", "name", "size", "osd", "serial");
    for (size_t i = 0; i < cnt; i++) {
        std::string sz = HexUtilPOpen("echo -n $(lsblk -n -d -o SIZE %s)", matchedDevs[i].c_str());
        std::string ids = HexUtilPOpen(HEX_SDK " ceph_get_ids_by_dev %s", matchedDevs[i].c_str());
        std::string sn = HexUtilPOpen(HEX_SDK " ceph_get_sn_by_dev %s", matchedDevs[i].c_str());
        printf(OSD_FMT, i + 1, matchedDevs[i].c_str(), sz.c_str(), ids.c_str(), sn.c_str());
    }
    printf(OSD_F_FMT);

    // 2. User input
    std::string input;
    size_t index = 0;
    CliReadLine("Enter the index to demote: ", input);
    if (!HexParseUInt(input.c_str(), 1, cnt, &index)) {
        CliPrintf("Invalid index, cancelled.");
        return CLI_SUCCESS;
    }
    // 3. Demote disk
    if (HexUtilSystemF(0, 0, HEX_SDK " ceph_osd_demote_disk %s", matchedDevs[index - 1].c_str())) {
        CliPrintf("Fail to demote this disk.\nCheck if cache has enough disks or if ceph is still recovering!");
        return CLI_SUCCESS;
    }
    return CLI_SUCCESS;
}

static int CephCacheFlush(int argc, const char** argv)
{
    if (argc > 2 /* [0]="flush" [1]="backpool" */)
        return CLI_INVALID_ARGS;

    std::string backPool;
    if (argc == 2) {
        backPool = argv[1];
    } else {
        int index;
        std::string optCmd = std::string(HEX_SDK) + " ceph_backpool_cache_list";
        std::string descCmd = std::string(HEX_SDK) + " -v ceph_backpool_cache_list";
        if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &backPool, "Enter index of back pool to create cache for: ") != CLI_SUCCESS) {
            CliPrintf("No cache tier available or invalid index chosen");
            return CLI_SUCCESS;
        }
    }

    // handle one liner case when backPool does not exist. ex: flush nosuchpool
    std::string validBackPool = HexUtilPOpen(HEX_SDK " ceph_get_pool_in_cacheable_backpool %s", backPool.c_str());
    if (validBackPool.empty()) {
        CliPrintf("Pool %s either does not support cache tiering or does not exist", backPool.c_str());
        return CLI_UNEXPECTED_ERROR;
    }

    std::string cachePool = HexUtilPOpen(HEX_SDK " ceph_get_cache_by_backpool %s", backPool.c_str());
    if (cachePool.empty()) {
        CliPrintf("Failed to find cache associated with backpool: %s.", backPool.c_str());
    } else {
        std::string onOffMsgs = HexUtilPOpen(HEX_SDK " ceph_osd_test_cache %s", backPool.c_str());
        if (onOffMsgs == "off") {
            CliPrintf("Cache tiering of %s/%s is off.", backPool.c_str(), cachePool.c_str());
        } else {
            if (HexSpawn(0, HEX_SDK, "ceph_osd_cache_flush", backPool.c_str(), NULL) == 0)
                CliPrintf("Data in '%s/%s' are flushed.", backPool.c_str(), cachePool.c_str());
        }
    }

    return CLI_SUCCESS;
}

static int
CephStatusMain(int argc, const char** argv)
{
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    if (argc == 1) {
    }
    if (argc == 2 && strcmp(argv[1], "details") == 0) {
        if (HexSpawn(30, HEX_SDK, "ceph_status", "details", NULL) != 0)
            return CLI_UNEXPECTED_ERROR;
    } else {
        if (HexSpawn(30, HEX_SDK, "ceph_status", NULL) != 0)
            return CLI_UNEXPECTED_ERROR;
    }

    return CLI_SUCCESS;
}

static int
CephAutoScaleMain(int argc, const char** argv)
{
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    int index;
    std::string value;

    if (CliMatchCmdHelper(argc, argv, 1, "echo 'on\noff'", &index, &value, "Set pool autoscale:") != CLI_SUCCESS) {
        CliPrintf("Unknown action");
        return CLI_INVALID_ARGS;
    }

    switch (index) {
    case 0:
        HexSpawn(0, HEX_SDK, "ceph_pool_autoscale_set", "on", NULL);
        break;
    case 1:
        HexSpawn(0, HEX_SDK, "ceph_pool_autoscale_set", "off", NULL);
        HexSpawn(0, HEX_SDK, "ceph_adjust_pgs", NULL);
        break;
    }

    return CLI_SUCCESS;
}

static int
CephSetForceUseMpathDevicesMain(int argc, const char** argv)
{
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    int index;
    std::string value;

    if (CliMatchCmdHelper(
            argc,
            argv,
            1,
            "echo 'true\nfalse'",
            &index,
            &value,
            "Set to force to use multipath devices for Ceph: ")
        != CLI_SUCCESS) {
        CliPrintf("Unknown option");
        return CLI_INVALID_ARGS;
    }

    if (value == "true") {
        const ExecSyncResult sr = ExecBashSync(
            0,
            false,
            false,
            {},
            HEX_SDK " storage_set_force_use_mpath_devices_for_ceph"
        );
        if (sr.exitCode != 0) {
            return CLI_FAILURE;
        }
    } else {
        const ExecSyncResult ur = ExecBashSync(
            0,
            false,
            false,
            {},
            HEX_SDK " storage_unset_force_use_mpath_devices_for_ceph"
        );
        if (ur.exitCode != 0) {
            return CLI_FAILURE;
        }
    }

    return CLI_SUCCESS;
}

static int
CephListAvailDisksMain(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    std::string alldev = HexUtilPOpen(HEX_SDK " storage_list_available_disks");
    if (alldev.length() < 8 /* start with /dev/sdx */) {
        CliPrintf("No available disk.");
        return CLI_SUCCESS;
    }

    std::vector<std::string> devs = hex_string_util::split(alldev, ' ');
    uint32_t cnt = 0;
    printf(DISK_H_FMT, "index", "name", "size", "on_hours", "error", "serial");
    for (auto& d : devs) {
        if (d.length() == 0)
            continue;
        std::string sz = HexUtilPOpen("lsblk -n -d -o SIZE %s", d.c_str());
        if (sz.length() > 0 && sz[sz.length() - 1] == '\n')
            sz[sz.length() - 1] = '\0';
        cnt++;
        std::string age = HexUtilPOpen("smartctl -A %s | grep -i 'power.*hour' | awk '{print $NF}' | xargs", d.c_str());
        if (age.length() > 0 && age[age.length() - 1] == '\n')
            age[age.length() - 1] = '\0';
        std::string err = HexUtilPOpen("smartctl -A %s | grep -i Reallocated_Sector_Ct | awk '{print $NF}' | xargs", d.c_str());
        if (err.length() > 0 && err[err.length() - 1] == '\n')
            err[err.length() - 1] = '\0';
        std::string sn = HexUtilPOpen("smartctl -i %s | grep -i 'Serial number' | cut -d':' -f2 | xargs", d.c_str());
        printf(DISK_FMT, cnt, d.c_str(), sz.c_str(), age.c_str(), err.c_str(), (sn.length() <= 1) ? "NA" : sn.c_str());
    }
    printf(DISK_F_FMT);
    CliPrintf("Found %u available disk%s.", cnt, (cnt == 1) ? "" : "s");

    return CLI_SUCCESS;
}

static int
CephAddAvailDisksMain(int argc, const char** argv)
{
    std::string mode;
    if (argc > 2 /* [0]="add_avail" [1]="<[raw|encrypt]>" */) {
        return CLI_INVALID_ARGS;
    } else if (argc == 2) {
        // any user input mode which is not "force" falls back to "safe" mode
        mode = argv[1];
        if (mode != "encrypt") {
            mode = "raw";
        }
    }

    // 1. List avail disks
    std::string alldev = HexUtilPOpen(HEX_SDK " storage_list_available_disks");
    if (alldev.length() < 8 /* start with /dev/sdx */) {
        CliPrintf("No available disk.");
        return CLI_SUCCESS;
    }

    std::vector<std::string> allDevs = hex_string_util::split(alldev, ' ');
    uint32_t cnt = 0;

    printf(DISK_H_FMT, "index", "name", "size", "on_hours", "error", "serial");
    for (auto& d : allDevs) {
        std::string sz = HexUtilPOpen("lsblk --raw -n -d -o SIZE %s", d.c_str());
        if (sz.length() > 0 && sz[sz.length() - 1] == '\n')
            sz[sz.length() - 1] = '\0';
        cnt++;
        std::string age = HexUtilPOpen("smartctl -A %s | grep -i 'power.*hour' | awk '{print $NF}' | xargs", d.c_str());
        if (age.length() > 0 && age[age.length() - 1] == '\n')
            age[age.length() - 1] = '\0';
        std::string err = HexUtilPOpen("smartctl -A %s | grep -i Reallocated_Sector_Ct | awk '{print $NF}' | xargs", d.c_str());
        if (err.length() > 0 && err[err.length() - 1] == '\n')
            err[err.length() - 1] = '\0';
        std::string sn = HexUtilPOpen("smartctl -i %s | grep -i 'Serial number' | cut -d':' -f2 | xargs", d.c_str());
        printf(DISK_FMT, cnt, d.c_str(), sz.c_str(), age.c_str(), err.c_str(), (sn.length() <= 1) ? "NA" : sn.c_str());
    }
    printf(DISK_F_FMT);

    // 2. confirm
    if (mode.empty()) {
        int index;
        if (CliMatchCmdHelper(argc, argv, 2, "echo -e 'raw\nencrypt'", &index, &mode, "Disk protection mode:") != CLI_SUCCESS) {
            return CLI_INVALID_ARGS;
        }

        if (mode == "encrypt") {
            CliPrintf("Encrypt disk(s) to protect physical disk loss (beware of performance impacts).");
        } else if (mode == "raw") {
            CliPrintf("No disk encryption (default mode).");
        } else {
            return CLI_SUCCESS;
        }

        if (!CliReadConfirmation()) {
            return CLI_SUCCESS;
        }
    }

    // 3. Add this OSD
    cnt = 0;
    printf(DISK_F_FMT);
    for (auto& d : allDevs) {
        const ExecSyncResult ir = ExecBashSync(
            0,
            false,
            false,
            {},
            HEX_SDK " storage_is_das '" + d + "'");
        if (ir.exitCode == 0) {
            // handle direct-attached storage
            if (HexSystemF(0, HEX_SDK " ceph_osd_add_disk_%s %s", mode.c_str(), d.c_str()) != 0) {
                CliPrintf("Failed to add disk(%s) %s.", mode.c_str(), d.c_str());
            } else {
                CliPrintf("Added disk(%s) %s.", mode.c_str(), d.c_str());
            }
        }

        // do not automatically handle mpath devices

        cnt++;
    }
    printf(DISK_F_FMT);
    CliPrintf("Processed %u disk%s out of %u.", cnt, (cnt <= 1) ? "" : "s", allDevs.size());

    return CLI_SUCCESS;
}

static int
CephAddDiskMain(int argc, const char** argv)
{
    std::string mode = "raw";
    std::string device;
    if (argc > 3 /* [0]="add_disk" [1]="<[/dev/sdx]>" [2]="<[raw|encrypt]>" */) {
        return CLI_INVALID_ARGS;
    } else if (argc == 3) {
        device = argv[1];
        // any user input mode which is not "encrypt" falls back to "raw" mode
        mode = argv[2];
        if (mode != "encrypt") {
            mode = "raw";
        }
    } else if (argc == 2) {
        device = argv[1];
    }

    if (device.empty()) {
        // 1. List avail disks
        std::string alldev = HexUtilPOpen(HEX_SDK " storage_list_available_disks");
        if (alldev.length() < 8 /* start with /dev/sdx */) {
            CliPrintf("No available disk.");
            return CLI_SUCCESS;
        }

        std::vector<std::string> allDevs = hex_string_util::split(alldev, ' ');
        uint32_t cnt = 0;

        // 1. Display candidates
        printf(DISK_H_FMT, "index", "name", "size", "on_hours", "error", "serial");
        for (auto& d : allDevs) {
            if (d.length() < 8)
                continue;
            std::string sz = HexUtilPOpen("lsblk -n -d -o SIZE %s", d.c_str());
            if (sz.length() > 0 && sz[sz.length() - 1] == '\n')
                sz[sz.length() - 1] = '\0';
            cnt++;
            std::string age = HexUtilPOpen("smartctl -A %s | grep -i 'power.*hour' | awk '{print $NF}' | xargs", d.c_str());
            if (age.length() > 0 && age[age.length() - 1] == '\n')
                age[age.length() - 1] = '\0';
            std::string err = HexUtilPOpen("smartctl -A %s | grep -i Reallocated_Sector_Ct | awk '{print $NF}' | xargs", d.c_str());
            if (err.length() > 0 && err[err.length() - 1] == '\n')
                err[err.length() - 1] = '\0';
            std::string sn = HexUtilPOpen("smartctl -i %s| grep -i 'Serial number' | cut -d':' -f2 | xargs", d.c_str());
            printf(DISK_FMT, cnt, d.c_str(), sz.c_str(), age.c_str(), err.c_str(), (sn.length() <= 1) ? "NA" : sn.c_str());
        }
        printf(DISK_F_FMT);
        CliPrintf("Found %u available disk%s", cnt, (cnt == 1) ? "" : "s");

        // 2. User input
        std::string input;
        size_t index = 0;
        CliReadLine("Enter the index to add this disk into the pool: ", input);
        if (!HexParseUInt(input.c_str(), 1, cnt, &index)) {
            CliPrintf("Invalid index, cancelled");
            return CLI_SUCCESS;
        }
        if ((index - 1) < 0 || (index - 1) >= cnt) {
            CliPrintf("Invalid index, cancelled.");
            return CLI_SUCCESS;
        }
        device = allDevs[index - 1];

        int idx;
        if (CliMatchCmdHelper(
                argc,
                argv,
                2,
                "echo -e 'raw\nencrypt'",
                &idx,
                &mode,
                "Disk protection mode:")
            != CLI_SUCCESS) {
            return CLI_INVALID_ARGS;
        }

        if (mode == "encrypt") {
            CliPrintf("Encrypt disk(s) to protect physical disk loss (beware of performance impacts).");
        } else if (mode == "raw") {
            CliPrintf("No disk encryption (default mode).");
        } else {
            CliPrintf("Invalid mode, cancelled.");
            return CLI_SUCCESS;
        }

        if (!CliReadConfirmation()) {
            return CLI_SUCCESS;
        }
    }

    // 3. Add this OSD
    const ExecSyncResult ir = ExecBashSync(
        0,
        false,
        false,
        {},
        HEX_SDK " storage_is_das '" + device + "'");
    if (ir.exitCode == 0) {
        // handle direct-attached storage
        if (HexSystemF(0, HEX_SDK " ceph_osd_add_disk_%s %s", mode.c_str(), device.c_str()) != 0) {
            CliPrintf("Failed to add disk(%s) %s.", mode.c_str(), device.c_str());
        } else {
            CliPrintf("Added disk(%s) %s.", mode.c_str(), device.c_str());
        }
    } else {
        // handle mpath devices
        if (mode == "encrypt") {
            CliPrint("Encrypted mode on adding multipath devices is not yet supported.");
            return CLI_SUCCESS;
        }

        if (HexSystemF(0, HEX_SDK " ceph_osd_add_mpath_lvm %s", device.c_str()) != 0) {
            CliPrintf("Failed to add disk %s.", device.c_str());
        } else {
            CliPrintf("Added disk %s.", device.c_str());
        }
    }
    return CLI_SUCCESS;
}

static int
CephRemoveDiskMain(int argc, const char** argv)
{
    std::string mode = "safe";
    std::string device;
    if (argc > 3 /* [0]="remove_disk" [1]="<[/dev/sdx]>" [2]="<[safe|force]>" */) {
        return CLI_INVALID_ARGS;
    } else if (argc == 3) {
        device = argv[1];
        // any user input mode which is not "force" falls back to "safe" mode
        mode = argv[2];
        if (mode != "force")
            mode = "safe";
    } else if (argc == 2) {
        device = argv[1];
    }

    if (device.empty()) {
        // 0. List all OSDs can be removed
        std::string osddev = HexUtilPOpen(HEX_SDK " ceph_osd_list_disk");
        std::vector<std::string> allDevs = hex_string_util::split(osddev, ' ');

        // 1.a) return directly if no OSDs
        std::size_t cnt = allDevs.size();
        if (cnt == 0) {
            CliPrintf("No disk to be removed.");
            return CLI_SUCCESS;
        }

        // 1.b) display candidates
        printf(OSD_H_FMT, "index", "name", "size", "osd", "serial");
        for (std::size_t i = 0; i < cnt; i++) {
            std::string sz = HexUtilPOpen("echo -n $(lsblk -n -d -o SIZE %s)", allDevs[i].c_str());
            std::string ids = HexUtilPOpen(HEX_SDK " ceph_get_ids_by_dev %s", allDevs[i].c_str());
            std::string sn = HexUtilPOpen(HEX_SDK " ceph_get_sn_by_dev %s", allDevs[i].c_str());
            printf(OSD_FMT, i + 1, allDevs[i].c_str(), sz.c_str(), ids.c_str(), sn.c_str());
        }
        printf(OSD_F_FMT);

        // 2. User input
        std::string input;
        std::size_t index = 0;
        CliReadLine("Enter the index of disk to be removed: ", input);
        if (!HexParseUInt(input.c_str(), 1, cnt, &index)) {
            CliPrintf("Invalid index, cancelled.");
            return CLI_SUCCESS;
        }
        if ((index - 1) < 0 || (index - 1) >= cnt) {
            CliPrintf("Invalid index, cancelled.");
            return CLI_SUCCESS;
        }
        device = allDevs[index - 1];

        int idx;
        if (CliMatchCmdHelper(argc, argv, 2, "echo -e 'safe\nforce'", &idx, &mode, "Disk removal mode:") != CLI_SUCCESS)
            return CLI_INVALID_ARGS;

        if (mode == "safe")
            CliPrintf("safe mode takes longer by attempting to migrate data on disk(s).");
        else if (mode == "force")
            CliPrintf("force mode immediately destroys disk data so USE IT AT YOUR OWN RISKS.");
        else
            return CLI_SUCCESS;

        if (!CliReadConfirmation())
            return CLI_SUCCESS;
    }

    // 3. remove this disk
    if (HexSystemF(0, HEX_SDK " ceph_osd_remove_disk %s %s", device.c_str(), mode.c_str()) != 0)
        CliPrintf("Failed to remove disk %s with %s mode.", device.c_str(), mode.c_str());
    else
        CliPrintf("Job to remove disk %s is scheduled.", device.c_str());

    return CLI_SUCCESS;
}

static int
CephRemoveExistMain(int argc, const char** argv)
{
    std::string mode;
    if (argc > 2 /* [0]="remove_exist" [1]="<[safe|force]>" */) {
        return CLI_INVALID_ARGS;
    } else if (argc == 2) {
        // any user input mode which is not "force" falls back to "safe" mode
        mode = argv[1];
        if (mode != "force")
            mode = "safe";
    }

    // 0. list all OSDs can be removed
    std::string osddev = HexUtilPOpen(HEX_SDK " ceph_osd_list_disk");
    std::vector<std::string> allDevs = hex_string_util::split(osddev, ' ');

    // 1.a) return directly if no OSDs
    std::size_t cnt = allDevs.size();
    if (cnt == 0) {
        CliPrintf("No disk to be removed.");
        return CLI_SUCCESS;
    }

    // 1.b) display candidates
    printf(OSD_H_FMT, "index", "name", "size", "osd", "serial");
    for (std::size_t i = 0; i < cnt; i++) {
        std::string sz = HexUtilPOpen("echo -n $(lsblk -n -d -o SIZE %s)", allDevs[i].c_str());
        std::string ids = HexUtilPOpen(HEX_SDK " ceph_get_ids_by_dev %s", allDevs[i].c_str());
        std::string sn = HexUtilPOpen(HEX_SDK " ceph_get_sn_by_dev %s", allDevs[i].c_str());
        printf(OSD_FMT, i + 1, allDevs[i].c_str(), sz.c_str(), ids.c_str(), sn.c_str());
    }
    printf(OSD_F_FMT);

    // 2. confirm
    if (mode.empty()) {
        int idx;
        if (CliMatchCmdHelper(argc, argv, 2, "echo -e 'safe\nforce'", &idx, &mode, "Disk removal mode:") != CLI_SUCCESS)
            return CLI_INVALID_ARGS;

        if (mode == "safe")
            CliPrintf("safe mode takes longer by attempting to migrate data on disk(s).");
        else if (mode == "force")
            CliPrintf("force mode immediately destroys disk data so USE IT AT YOUR OWN RISKS.");
        else
            return CLI_SUCCESS;

        if (!CliReadConfirmation())
            return CLI_SUCCESS;
    }

    // 3. remove all existing disks
    cnt = 0;
    printf(DISK_F_FMT);
    for (auto& d : allDevs) {
        if (d.length() == 0)
            continue;

        if (HexSystemF(0, HEX_SDK " ceph_osd_remove_disk %s %s", d.c_str(), mode.c_str()) != 0) {
            CliPrintf("Failed to remove disk %s with %s mode for storage cannot become healthy without it.", d.c_str(), mode.c_str());
            break;
        } else {
            CliPrintf("Job to remove disk %s is scheduled.", d.c_str());
            cnt++;
        }
    }
    printf(DISK_F_FMT);
    CliPrintf(
        "Job to process %u disk%s out of %u %s scheduled.",
        cnt,
        (cnt <= 1) ? "" : "s",
        allDevs.size(),
        (cnt <= 1) ? "is" : "are");

    return CLI_SUCCESS;
}

static int
CephRemoveOsdMain(int argc, const char** argv)
{
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    CliList devices;
    CliList descriptions;
    std::string oid;
    int index;

    std::string optCmd = std::string(HEX_SDK) + " ceph_osd_down_list";
    std::string descCmd = std::string(HEX_SDK) + " -v ceph_osd_down_list";
    if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &oid, "Enter osd id to be removed: ") != CLI_SUCCESS) {
        CliPrintf("there is no down osd or it's an invalid id");
        return CLI_SUCCESS;
    }

    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    if (HexUtilSystemF(0, 0, HEX_SDK " ceph_osd_remove %s", oid.c_str()))
        HexLogError("Remove osd.%s failed.", oid.c_str());
    else
        CliPrintf("Remove osd.%s successfully.", oid.c_str());

    return CLI_SUCCESS;
}

static int
CephRebalanceMain(int argc, const char** argv)
{
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    int64_t size;
    std::string rf;

    if (!CliReadInputStr(argc, argv, 1, "Input replication factor(1/2/3): ", &rf) || !HexParseInt(rf.c_str(), 1, 3, &size)) {
        CliPrint("bad rf value (1/2/3)");
        return CLI_INVALID_ARGS;
    }

    HexUtilSystemF(0, 0, HEX_SDK " ceph_pool_replicate_set %lu", size);
    HexUtilSystemF(0, 0, HEX_SDK " ceph_adjust_pgs");

    return CLI_SUCCESS;
}

static int
CephConfigSyncMain(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    HexUtilSystem(0, 0, "/usr/sbin/hex_config sync_ceph_config", NULL);

    return CLI_SUCCESS;
}

static int
CephMaintenanceMain(int argc, const char** argv)
{
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    CliList options;
    int index;
    std::string value;

    options.push_back("on");
    options.push_back("off");
    options.push_back("status");

    if (CliMatchListHelper(argc, argv, 1, options, &index, &value) != 0) {
        CliPrintf("Unknown command");
        return CLI_INVALID_ARGS;
    }

    switch (index) {
    case 0:
        HexSpawn(0, HEX_SDK, "ceph_enter_maintenance", NULL);
        break;
    case 1:
        HexSpawn(0, HEX_SDK, "ceph_leave_maintenance", NULL);
        break;
    case 2:
        HexSpawn(0, HEX_SDK, "ceph_maintenance_status", NULL);
        break;
    }

    return CLI_SUCCESS;
}

static int CephCreateNodeGroup(int argc, const char** argv)
{
    if (argc < 3) {
        HexSpawn(0, HEX_SDK, " ceph_node_group_list", NULL, NULL);
        return CLI_INVALID_ARGS;
    }

    std::string group = argv[1];
    std::string nodes;
    for (int i = 1; i < argc; i++) {
        nodes.append(argv[i]);
        if (i < (argc - 1))
            nodes.append(" ");
    }

    int ret = 0;
    if ((ret = HexUtilSystemF(0, 0, HEX_SDK " ceph_create_node_group %s %s", group.c_str(), nodes.c_str()))) {
        HexLogError("Failed to add a ceph group (%s), containing nodes (%s)", group.c_str(), nodes.c_str());
        CliPrintf("\n--\nFailed to add node group.");
    }

    return CLI_SUCCESS;
}

static int CephRemoveNodeGroup(int argc, const char** argv)
{
    if (argc < 2) {
        HexSpawn(0, HEX_SDK, " ceph_node_group_list", NULL, NULL);
        return CLI_INVALID_ARGS;
    }

    if (strcmp(argv[1], "default") == 0) {
        // default bucket cannot be removed
        HexLogError("default is a must-have bucket by system.");
    } else {
        std::string group = argv[1];
        std::string backPool = group + "-pool";

        // confirm the decision to disable cache and remove group
        CliPrintf("\nWarning: removing group will first disable its corresponding cache, delete volumes and pools as well as adjusting crush rules, resulting in data movements. ALL DATA IN MATCHING POOLS WILL BE LOST!");
        if (CliReadConfirmation()) {
            int ret = 0;
            // Disable cache before removing group
            if ((ret = HexUtilSystemF(0, 0, HEX_SDK " ceph_osd_disable_cache %s", backPool.c_str()))) {
                HexLogError("Failed to disable %s cache(err=%d)", backPool.c_str(), ret);
            }

            if ((ret = HexUtilSystemF(0, 0, HEX_SDK " ceph_remove_node_group %s", group.c_str()))) {
                HexLogError("Failed to add a ceph group (%s)", group.c_str());
                CliPrintf("\n--\nFailed to remove node group.");
            }
        }
    }

    return CLI_SUCCESS;
}

static int CephNodeGroupList(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, " ceph_node_group_list", NULL, NULL);

    return CLI_SUCCESS;
}

static int CephCreateSsdPool(int argc, const char** argv)
{
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    std::string group = (argc == 2) ? argv[1] : "default";

    int ret = 0;
    if ((ret = HexUtilSystemF(0, 0, HEX_SDK " ceph_create_group_ssdpool %s", group.c_str()))) {
        HexLogError("Failed to add SSD pool (%s)", group.c_str());
        CliPrintf("\n--\nFailed to add SSD pool.");
    }

    return CLI_SUCCESS;
}

static int CephRemoveSsdPool(int argc, const char** argv)
{
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    std::string group = (argc == 2) ? argv[1] : "default";

    // confirm the decision to remove SSD pool
    CliPrintf("\nWarning: ALL DATA IN SSDPOOL OF SPECIFIED GROUP WILL BE LOST!");
    if (CliReadConfirmation()) {
        int ret = 0;
        // Disable cache before removing group
        if ((ret = HexUtilSystemF(0, 0, HEX_SDK " ceph_remove_group_ssdpool %s", group.c_str()))) {
            HexLogError("Failed to remove ssdpool in %s group (err=%d)", group.c_str(), ret);
            CliPrintf("\n--\nFailed to remove group ssdpool.");
        }
    }

    return CLI_SUCCESS;
}


// ---------------------------------------------------------------------------
// Device tiers (#840).
//
// A device tier is a named set of OSDs that gets its own CRUSH device class,
// its own CRUSH rule, its own pool and its own Cinder volume type -- all four
// carrying the tier's name -- plus an entry in the storage tier registry, which
// is what generates its Cinder backend.
//
// Every rule about what a tier may be called and which OSDs it may hold is
// enforced here, and nowhere else, because there is nowhere else it can be:
// the registry is an indexed tuning array (cinder.storage.tier.%d.name), the
// cinder CONFIG_MODULE has no validate slot, ConfigString::parse always returns
// true, TuningStringArray drops its ValidateType, and `hex_config
// validate_tuning_value` compares the literal key name -- which never equals
// an indexed one. The CLI is the gatekeeper.
//
// The rules also all come from measurement rather than caution; each one below
// says which one.
// ---------------------------------------------------------------------------

#define TIER_OSD_H_FMT " %6s  %14s  %14s  %8s\n--\n"
#define TIER_OSD_FMT " %6s  %14s  %14s  %8s\n"

static const char* LABEL_TIER_NAME = "Enter the device tier name (required): ";
static const char* LABEL_TIER_OSDS = "Enter the OSD ids, space separated (required): ";

struct CephOsdRow {
    std::string id;
    std::string host;
    std::string cls;
    std::string status;
};

// Run one of sdk_ceph.sh's device tier queries and split its stdout into lines.
//
// Arguments are passed as arguments. ExecBashSync -- the obvious tool here --
// runs `/bin/bash -c "set -o pipefail && " + command`, so anything appended to
// a command string is shell syntax, not data. Two of these queries take a
// name that came out of the registry, and the registry is writable without
// passing through this file at all: the policy chain and `hex_config commit
// <settings>` both write it, which is why _ceph_device_tier_registry says an
// entry can hold any byte. A tier called `x; rm -rf /` would be a second
// command. ExecSync execvp()s the program with an argv, so it cannot be.
//
// False means the question was not answered. Every one of those queries returns
// non-zero instead of an empty answer when it cannot read the cluster, and the
// callers here refuse to decide on that: a name checked against a list that
// failed to load is not checked, and reading "cannot tell" as "nothing there"
// is the whole family of bugs #840 kept finding in the layer below.
static bool
CephDeviceTierQuery(const std::vector<std::string>& args, std::vector<std::string>& lines)
{
    Cmd c;
    c.path = HEX_SDK;
    c.args = args;
    c.captureStdout = true;
    c.captureStderr = true;

    const ExecSyncResult r = ExecSync(0, c);
    if (r.exitCode != 0) {
        return false;
    }

    for (const auto& l : hex_string_util::split(r.stdoutOutput, '\n')) {
        if (l.length()) {
            lines.push_back(l);
        }
    }

    return true;
}

// The states ceph_device_tier_names reports, and what this CLI may do
// with each. Ownership is the registry, never the shape of the Ceph objects:
// a device class with a same-named rule and pool is what a device tier looks
// like, and customers hand-build exactly that shape, so treating a lookalike
// as one of ours is how this CLI would come to delete someone else's storage.
enum CephDeviceTierState {
    TIER_NONE,             // this CLI has never heard of the name
    TIER_REGISTERED,       // ours, and Ceph has the class, the rule and the pool
    TIER_REGISTRY_PARTIAL, // ours, and Ceph has some of those three
    TIER_REGISTRY_ONLY,    // ours, and Ceph is known to have none of them
    TIER_UNMANAGED,        // Ceph has all three; the registry does not list it
};

// Read the state of every name ceph_device_tier_names knows.
static bool
CephDeviceTierStates(std::vector<std::pair<CephDeviceTierState, std::string>>& tiers)
{
    std::vector<std::string> lines;

    if (!CephDeviceTierQuery({ "ceph_device_tier_names" }, lines)) {
        return false;
    }

    for (const auto& l : lines) {
        const std::size_t bar = l.find('|');
        if (bar == std::string::npos) {
            return false;
        }
        const std::string state = l.substr(0, bar);
        const std::string name = l.substr(bar + 1);
        if (state == "registered") {
            tiers.push_back({ TIER_REGISTERED, name });
        } else if (state == "registry-partial") {
            tiers.push_back({ TIER_REGISTRY_PARTIAL, name });
        } else if (state == "registry-only") {
            tiers.push_back({ TIER_REGISTRY_ONLY, name });
        } else if (state == "unmanaged") {
            tiers.push_back({ TIER_UNMANAGED, name });
        } else {
            // An unrecognised state is not a state to guess at
            return false;
        }
    }

    return true;
}

// A tier's name becomes a device class, a CRUSH rule, a pool and a volume type,
// so what it may contain is the intersection of what those four accept. Ceph is
// the strict side: `osd crush class create` rejects '.', ' ', '/', ':' and
// non-ASCII (measured, F10). What it does NOT reject is the empty string -- it
// returns 0 and creates a class with no name -- so the check cannot be left to
// the layer that will actually run the command.
static bool
CephDeviceTierNameOk(const std::string& tier)
{
    if (tier.empty()) {
        CliPrintf("A device tier name is required.");
        return false;
    }

    for (std::size_t i = 0; i < tier.length(); i++) {
        const char c = tier[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
                || c == '-' || c == '_')) {
            CliPrintf("Invalid device tier name '%s': Ceph accepts only letters, digits, '-' and '_' in a device class name.",
                tier.c_str());
            return false;
        }
    }

    // A leading '-' is read as an option by everything the name is handed to,
    // starting with `ceph osd crush set-device-class`.
    if (tier[0] == '-') {
        CliPrintf("Invalid device tier name '%s': it cannot start with '-'.", tier.c_str());
        return false;
    }

    // config_cinder.cpp's scan for the legacy tiering layout matches "-pool"
    // and "-ssd" as substrings, not as suffixes (the grep at :1070 and the
    // find() at :1077), so a tier holding either would be claimed by that scan
    // as well as by the registry and end up with two conflicting Cinder
    // backends.
    if (tier.find("-pool") != std::string::npos || tier.find("-ssd") != std::string::npos) {
        CliPrintf("Invalid device tier name '%s': it must not contain '-pool' or '-ssd', which the legacy tiering scan claims.",
            tier.c_str());
        return false;
    }

    return true;
}

// Is this name free to become a device tier?
//
// The comparison is whole-name, never a substring: os_volume_type_create's own
// existence check is an unanchored grep, which answers yes for "seki1" when
// only "seki1-ssd" exists, so it cannot be reused to decide this.
//
// A name the registry already lists is not a collision with itself, and
// *existing says so: re-running create is how a tier of ours that is missing a
// piece gets completed, and hex_sdk's create is idempotent step by step.
//
// A name that merely LOOKS like a device tier on the Ceph side is a collision.
// It is reported like any other, because that is what it is: the registry says
// this CLI did not build it, and a class with a same-named rule and pool is a
// shape customers hand-build. Adopting it would make someone else's storage
// into a Cinder backend, and then offer it for deletion.
static bool
CephDeviceTierNameFree(const std::string& tier, bool* existing)
{
    std::vector<std::string> taken;
    std::vector<std::pair<CephDeviceTierState, std::string>> tiers;

    *existing = false;

    if (!CephDeviceTierQuery({ "ceph_device_tier_names_taken" }, taken)
        || !CephDeviceTierStates(tiers)) {
        CliPrintf("Cannot read the device tier registry and the existing device class, CRUSH rule, pool and volume type names, so it cannot be established that '%s' is free. Not creating anything.",
            tier.c_str());
        return false;
    }

    for (const auto& t : tiers) {
        if (t.second != tier) {
            continue;
        }
        if (t.first == TIER_UNMANAGED) {
            // Terminal here, decided from THIS snapshot. Breaking out to the
            // collision loop below would settle ownership using `taken`, which
            // was read BEFORE this list: a lookalike that became complete
            // between the two reads is absent from `taken`, the name comes
            // back free, and the idempotent create adopts the foreign objects
            // -- exactly what telling the states apart is here to prevent.
            CliPrintf("The name '%s' is a device class with a CRUSH rule and a pool of the same name, but it is not in the storage tier registry -- so it was not created here. Not creating anything.",
                tier.c_str());
            CliPrintf("This CLI does not manage objects it did not register. If '%s' is a device tier built here whose registration did not complete, finish it with 'hex_sdk ceph_device_tier_create %s <osd id>...'.",
                tier.c_str(), tier.c_str());
            return false;
        }
        // registered, registry-partial or registry-only: the registry says
        // this one is ours, and re-running create is how a tier that is
        // missing a piece gets completed.
        *existing = true;
        return true;
    }

    for (const auto& t : taken) {
        const std::size_t bar = t.find('|');
        if (bar == std::string::npos) {
            continue;
        }
        if (t.substr(bar + 1) != tier) {
            continue;
        }

        const std::string kind = t.substr(0, bar);
        std::string what = kind;
        if (kind == "class") {
            what = "CRUSH device class";
        } else if (kind == "rule") {
            what = "CRUSH rule";
        } else if (kind == "pool") {
            what = "Ceph pool";
        } else if (kind == "vtype") {
            what = "Cinder volume type";
        }

        CliPrintf("The name '%s' is already taken by a %s. A device tier's name has to be free as all four of a device class, a CRUSH rule, a pool and a volume type.",
            tier.c_str(), what.c_str());
        // Deliberately not offered as something this CLI will take over. If
        // those objects were built here and only the registry entry is
        // missing, the repair is one explicit command that says what it is
        // doing; if they were not, nothing here should touch them.
        CliPrintf("This CLI does not manage objects it did not register. If '%s' is a device tier built here whose registration did not complete, finish it with 'hex_sdk ceph_device_tier_create %s <osd id>...'.",
            tier.c_str(), tier.c_str());
        return false;
    }

    return true;
}

// Every OSD the cluster knows, with its host, its device class and its state.
static bool
CephDeviceTierOsdTable(std::vector<CephOsdRow>& rows)
{
    std::vector<std::string> lines;

    if (!CephDeviceTierQuery({ "ceph_device_tier_osd_table" }, lines)) {
        CliPrintf("Cannot read the OSD list. Not going any further -- an OSD id that has not been checked against the cluster would have CRUSH invent a bucket for it.");
        return false;
    }

    for (const auto& l : lines) {
        const std::vector<std::string> f = hex_string_util::split(l, '|');
        if (f.size() < 4) {
            CliPrintf("Cannot read the OSD list: unexpected row '%s'.", l.c_str());
            return false;
        }
        rows.push_back({ f[0], f[1], f[2], f[3] });
    }

    if (rows.empty()) {
        CliPrintf("This cluster has no OSDs.");
        return false;
    }

    return true;
}

static void
CephDeviceTierPrintOsdTable(const std::vector<CephOsdRow>& rows)
{
    printf(TIER_OSD_H_FMT, "osd", "host", "device class", "state");
    for (const auto& r : rows) {
        printf(TIER_OSD_FMT, r.id.c_str(), r.host.c_str(),
            r.cls.length() ? r.cls.c_str() : "-", r.status.c_str());
    }
}

// "0" and "osd.0" both name OSD 0. Ids the cluster does not know are refused
// here, and repeats are folded, so that what is confirmed below is what is
// asked for.
static bool
CephDeviceTierParseOsds(const std::vector<std::string>& args,
    const std::vector<CephOsdRow>& rows,
    std::vector<std::string>& ids,
    std::vector<CephOsdRow>& chosen)
{
    for (const auto& a : args) {
        std::string id = a;
        if (id.compare(0, 4, "osd.") == 0) {
            id = id.substr(4);
        }
        if (id.empty() || id.find_first_not_of("0123456789") != std::string::npos) {
            CliPrintf("Invalid OSD id: '%s'. Give an id as 0 or osd.0.", a.c_str());
            return false;
        }

        const CephOsdRow* found = NULL;
        for (const auto& r : rows) {
            if (r.id == id) {
                found = &r;
                break;
            }
        }
        if (found == NULL) {
            CliPrintf("No such OSD: '%s'.", a.c_str());
            return false;
        }

        if (std::find(ids.begin(), ids.end(), id) == ids.end()) {
            ids.push_back(id);
            chosen.push_back(*found);
        }
    }

    if (ids.empty()) {
        CliPrintf("At least one OSD is required.");
        return false;
    }

    return true;
}

// Read the OSD list from the arguments, or list the candidates and ask.
static bool
CephDeviceTierReadOsds(int argc, const char** argv, int argidx,
    const std::vector<CephOsdRow>& rows,
    std::vector<std::string>& ids,
    std::vector<CephOsdRow>& chosen)
{
    std::vector<std::string> args;

    if (argc > argidx) {
        for (int i = argidx; i < argc; i++) {
            args.push_back(argv[i]);
        }
    } else {
        CephDeviceTierPrintOsdTable(rows);
        std::string input;
        CliReadLine(LABEL_TIER_OSDS, input);
        for (const auto& a : hex_string_util::split(input, ' ')) {
            if (a.length()) {
                args.push_back(a);
            }
        }
    }

    return CephDeviceTierParseOsds(args, rows, ids, chosen);
}

// What starts moving the moment these OSDs change device class.
//
// This is the impact the operator is being asked to accept, and it is not the
// same question as "which pool will the new tier serve". A class-restricted
// rule loses a candidate as soon as the class changes, so the pools bound to
// that rule start remapping at the first step -- not at the later one that
// binds the tier's own pool. On the 1cc, where every pool is on the
// class-agnostic replicated_rule, this list is empty and nothing moves until
// that later step; on mixed hardware with rule-ssd / rule-hdd in use it is not
// (measured, F3 and F13).
//
// False means one of those lists could not be read. Showing "(none)" for an
// answer nobody got would be asking for consent to an unknown blast radius, so
// it stops instead.
static bool
CephDeviceTierPrintImpact(const std::vector<std::string>& classes)
{
    for (const auto& c : classes) {
        Cmd cmd;
        cmd.path = HEX_SDK;
        cmd.args = { "ceph_device_tier_class_users", c };
        cmd.captureStdout = true;
        cmd.captureStderr = true;

        const ExecSyncResult r = ExecSync(0, cmd);
        if (r.exitCode != 0) {
            CliPrintf("Cannot tell which pools select OSDs through device class '%s', so the effect of this change cannot be shown. Not proceeding.",
                c.c_str());
            return false;
        }

        // Trimmed by hand: hex_string_util::strip does nothing at all when the
        // whole string is in its character set (find_first_not_of returns npos
        // and neither end is erased), so an answer of just a newline -- which
        // is what "no pool selects through this class" looks like -- would keep
        // its length and print as a blank list instead of as nothing.
        std::string pools = r.stdoutOutput;
        const std::size_t first = pools.find_first_not_of(" \t\r\n");
        if (first == std::string::npos) {
            pools.clear();
        } else {
            pools.erase(0, first);
            pools.erase(pools.find_last_not_of(" \t\r\n") + 1);
        }

        CliPrintf("   %s: %s", c.c_str(),
            pools.length() ? pools.c_str() : "no pool selects through this class");
    }

    return true;
}

// The distinct device classes the chosen OSDs carry now, in the order they
// first appear. An OSD with no class contributes nothing: there is no rule
// selecting through a class it does not have.
static std::vector<std::string>
CephDeviceTierClassesOf(const std::vector<CephOsdRow>& chosen)
{
    std::vector<std::string> classes;

    for (const auto& r : chosen) {
        if (r.cls.length() && std::find(classes.begin(), classes.end(), r.cls) == classes.end()) {
            classes.push_back(r.cls);
        }
    }

    return classes;
}

// Hand the work to hex_sdk without a shell. The name and the ids have already
// been validated, so this is not the last line of defence -- but passing them
// as separate arguments means a name that reaches this from somewhere else
// still cannot become shell syntax.
static int
CephDeviceTierSpawn(const char* subcmd, const std::string& tier, const std::vector<std::string>& ids)
{
    std::vector<const char*> args;

    args.push_back(HEX_SDK);
    args.push_back(subcmd);
    args.push_back(tier.c_str());
    for (const auto& i : ids) {
        args.push_back(i.c_str());
    }
    args.push_back(NULL);

    // The child writes straight to the terminal while anything CliPrintf left
    // in this process's buffer is still sitting there -- and when stdout is
    // not a tty (a piped session, a script) that buffer is not flushed per
    // line, so a warning printed before this call can come out after the
    // output of the command it was warning about.
    fflush(stdout);

    return HexExitStatus(HexSpawnV(0, (char* const*)&args[0]));
}

// Name a device tier this CLI owns: from the arguments, or by picking one.
// *state comes back so the caller can tell a tier whose objects are there from
// one that is only a registry entry.
//
// Only names the registry lists are offered, and only those are accepted --
// whether Ceph has all, some or none of their objects. A Ceph structure that
// merely has the shape of a device tier is refused by name here rather than
// listed and acted on: update and delete are the two commands that would
// otherwise remap or destroy it.
//
// The name is put through the same guard create uses even though it came from
// the registry, because that is exactly why: the registry is written by the
// policy chain and by `hex_config commit <settings>` without passing through
// this file, so an entry can hold any byte. Nothing downstream builds a shell
// command out of it any more, but a name Ceph itself will not accept is not
// one to hand to Ceph, and a name starting with '-' is an option to everything
// it reaches.
//
// Refusing when the list cannot be read is deliberate -- "no such device tier"
// and "the cluster did not answer" are different answers, and reporting the
// second as the first is what sends an operator to re-create something that
// already exists.
static bool
CephDeviceTierPick(int argc, const char** argv, int argidx, std::string& tier,
    CephDeviceTierState* state)
{
    std::vector<std::pair<CephDeviceTierState, std::string>> tiers;
    std::vector<std::string> owned;

    *state = TIER_NONE;

    if (!CephDeviceTierStates(tiers)) {
        CliPrintf("Cannot read the device tier registry. Not going any further -- which device tiers this CLI manages cannot be established without it.");
        return false;
    }

    for (const auto& t : tiers) {
        if (t.first == TIER_REGISTERED || t.first == TIER_REGISTRY_PARTIAL
            || t.first == TIER_REGISTRY_ONLY) {
            owned.push_back(t.second);
        }
    }

    if (argc > argidx) {
        // A name was given, so its own state is the answer -- checked before
        // the "nothing to pick from" case, because a named lookalike deserves
        // to be told it is a lookalike rather than that no tiers exist.
        tier = argv[argidx];
    } else {
        if (owned.empty()) {
            CliPrintf("There are no device tiers.");
            return false;
        }
        for (std::size_t i = 0; i < owned.size(); i++) {
            CliPrintf("   %lu) %s", (unsigned long)(i + 1), owned[i].c_str());
        }
        std::string input;
        std::size_t index = 0;
        CliReadLine("Enter the index of the device tier: ", input);
        if (!HexParseUInt(input.c_str(), 1, owned.size(), &index)) {
            CliPrintf("Invalid index.");
            return false;
        }
        tier = owned[index - 1];
    }

    for (const auto& t : tiers) {
        if (t.second == tier) {
            *state = t.first;
            break;
        }
    }

    if (*state == TIER_UNMANAGED) {
        CliPrintf("'%s' is a device class with a CRUSH rule and a pool of the same name, but it is not in the storage tier registry -- so it was not created here and this CLI does not manage it. Nothing has been changed.",
            tier.c_str());
        CliPrintf("If it was created here and only its registration is missing, register it with 'hex_sdk cinder_apply_storage_tier_creation %s'; hex_sdk's ceph_device_tier_* functions operate on it directly if that is really what you want.",
            tier.c_str());
        return false;
    }
    if (*state == TIER_NONE) {
        if (owned.empty()) {
            CliPrintf("There are no device tiers.");
        } else {
            CliPrintf("No such device tier: '%s'.", tier.c_str());
        }
        return false;
    }

    if (!CephDeviceTierNameOk(tier)) {
        CliPrintf("That name is in the storage tier registry but is not one this CLI can act on. It was written by something other than this command -- the policy file, or 'hex_config commit'. Remove it with 'hex_sdk cinder_apply_storage_tier_deletion' and register a valid name instead.");
        return false;
    }

    return true;
}

static int
CephDeviceTierCreate(int argc, const char** argv)
{
    /* [0]="create" [1]=<tier name> [2...]=<osd id> */
    std::string tier;

    if (argc > 1) {
        tier = argv[1];
    } else {
        CliReadLine(LABEL_TIER_NAME, tier);
    }

    if (!CephDeviceTierNameOk(tier)) {
        return CLI_INVALID_ARGS;
    }

    std::vector<CephOsdRow> rows;
    if (!CephDeviceTierOsdTable(rows)) {
        return CLI_FAILURE;
    }

    bool existing = false;
    if (!CephDeviceTierNameFree(tier, &existing)) {
        return CLI_INVALID_ARGS;
    }

    // Already known as a device tier -- by the registry, by Ceph, or by both.
    std::vector<std::string> members;
    if (existing) {
        for (const auto& r : rows) {
            if (r.cls == tier) {
                members.push_back(r.id);
            }
        }
    }

    // The Ceph side is there. Creating it again cannot change which OSDs it
    // holds -- that is update -- but it is how a tier that got as far as its
    // Ceph objects and then failed at the volume type or the registry gets
    // completed, which is the state tier list flags. Nothing moves, so there
    // is nothing to confirm and no reason to ask which OSDs; the tier's own
    // members are what hex_sdk is given, because its usage requires at least
    // one and passing none would be rejected before it could do anything.
    //
    // A tier that is in the registry with nothing on the Ceph side has no
    // members to pass, and building it IS a real create -- so that case falls
    // through to the ordinary path below, confirmation included.
    if (!members.empty()) {
        if (argc > 2) {
            CliPrintf("Device tier '%s' already exists. 'tier create' cannot change which OSDs it holds -- use 'tier update %s <osd id>...' for that. Completing whatever is missing instead.",
                tier.c_str(), tier.c_str());
        }
        if (CephDeviceTierSpawn("ceph_device_tier_create", tier, members)) {
            HexLogError("Failed to complete device tier %s", tier.c_str());
            CliPrintf("\n--\nFailed to complete device tier %s.", tier.c_str());
            return CLI_FAILURE;
        }
        return CLI_SUCCESS;
    }

    std::vector<std::string> ids;
    std::vector<CephOsdRow> chosen;
    if (!CephDeviceTierReadOsds(argc, argv, 2, rows, ids, chosen)) {
        return CLI_INVALID_ARGS;
    }

    std::vector<std::string> hosts;
    std::string osdLine;
    for (const auto& r : chosen) {
        osdLine.append(" osd.").append(r.id);
        if (std::find(hosts.begin(), hosts.end(), r.host) == hosts.end()) {
            hosts.push_back(r.host);
        }
    }

    CliPrintf("\nDevice tier '%s' will be created on:", tier.c_str());
    CephDeviceTierPrintOsdTable(chosen);
    CliPrintf("Its pool is replicated across the %lu host(s) those OSDs are on, with a replication size of whichever is smaller: that host count, or the replication size of %s.",
        (unsigned long)hosts.size(), BUILTIN_BACKPOOL.c_str());

    // The confirmation goes here, before the first call that changes anything,
    // rather than before the step that binds the pool to the rule. Taking an
    // OSD out of a class that some rule selects through starts moving data at
    // that first step, so a confirmation after it would be asking about
    // something already under way. Cancelling leaves no class change behind
    // because no SDK call has been made yet.
    const std::vector<std::string> classes = CephDeviceTierClassesOf(chosen);
    if (classes.size()) {
        CliPrintf("\nThose OSDs are leaving the device classes they carry now. Data starts moving as soon as this is confirmed, for every pool whose CRUSH rule selects through one of them:");
        if (!CephDeviceTierPrintImpact(classes)) {
            return CLI_FAILURE;
        }
    }

    if (!CliReadConfirmation()) {
        return CLI_SUCCESS;
    }

    if (CephDeviceTierSpawn("ceph_device_tier_create", tier, ids)) {
        HexLogError("Failed to create device tier %s on%s", tier.c_str(), osdLine.c_str());
        CliPrintf("\n--\nFailed to create device tier %s.", tier.c_str());
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
CephDeviceTierUpdate(int argc, const char** argv)
{
    /* [0]="update" [1]=<tier name> [2...]=<osd id> */
    std::string tier;
    CephDeviceTierState state = TIER_NONE;

    if (!CephDeviceTierPick(argc, argv, 1, tier, &state)) {
        return CLI_INVALID_ARGS;
    }

    // Registered, but there is no class or rule to move members between yet.
    // hex_sdk would say "no such device tier", which is true of Ceph and
    // misleading about the registry.
    //
    // A partial tier does not come in here either: one holding a class and a
    // rule but no pool has members and can have them changed, and hex_sdk's
    // update checks the two objects it needs itself.
    if (state == TIER_REGISTRY_ONLY) {
        CliPrintf("Device tier '%s' is registered but has nothing on the Ceph side, so it has no members to change. Build it with 'tier create %s <osd id>...', or take the registry entry out with 'tier delete %s'.",
            tier.c_str(), tier.c_str(), tier.c_str());
        return CLI_INVALID_ARGS;
    }

    std::vector<CephOsdRow> rows;
    if (!CephDeviceTierOsdTable(rows)) {
        return CLI_FAILURE;
    }

    std::vector<std::string> before;
    for (const auto& r : rows) {
        if (r.cls == tier) {
            before.push_back(r.id);
        }
    }

    std::vector<std::string> ids;
    std::vector<CephOsdRow> chosen;
    if (!CephDeviceTierReadOsds(argc, argv, 2, rows, ids, chosen)) {
        return CLI_INVALID_ARGS;
    }

    std::string leaving;
    for (const auto& id : before) {
        if (std::find(ids.begin(), ids.end(), id) == ids.end()) {
            leaving.append(" osd.").append(id);
        }
    }
    std::string joining;
    for (const auto& id : ids) {
        if (std::find(before.begin(), before.end(), id) == before.end()) {
            joining.append(" osd.").append(id);
        }
    }

    // Nothing to consent to when the membership is not changing; hex_sdk says
    // so itself and does nothing.
    if (leaving.empty() && joining.empty()) {
        if (CephDeviceTierSpawn("ceph_device_tier_update", tier, ids)) {
            CliPrintf("\n--\nFailed to update device tier %s.", tier.c_str());
            return CLI_FAILURE;
        }
        return CLI_SUCCESS;
    }

    CliPrintf("\nDevice tier '%s' will consist of:", tier.c_str());
    CephDeviceTierPrintOsdTable(chosen);
    if (joining.length()) {
        CliPrintf("joining:%s", joining.c_str());
    }
    if (leaving.length()) {
        CliPrintf("leaving:%s -- left with no device class, not put back to what they carried before this tier",
            leaving.c_str());
    }

    // Unlike create, this tier's CRUSH rule already exists, so its own pool
    // starts remapping at the first class change too, not only the pools bound
    // to the classes the joining OSDs are leaving (F13).
    std::vector<std::string> classes = CephDeviceTierClassesOf(chosen);
    if (std::find(classes.begin(), classes.end(), tier) == classes.end()) {
        classes.push_back(tier);
    }
    CliPrintf("\nData starts moving as soon as this is confirmed, for every pool whose CRUSH rule selects through one of these device classes:");
    if (!CephDeviceTierPrintImpact(classes)) {
        return CLI_FAILURE;
    }

    if (!CliReadConfirmation()) {
        return CLI_SUCCESS;
    }

    if (CephDeviceTierSpawn("ceph_device_tier_update", tier, ids)) {
        HexLogError("Failed to update device tier %s", tier.c_str());
        CliPrintf("\n--\nFailed to update device tier %s.", tier.c_str());
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
CephDeviceTierDelete(int argc, const char** argv)
{
    /* [0]="delete" [1]=<tier name> */
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    std::string tier;
    CephDeviceTierState state = TIER_NONE;
    if (!CephDeviceTierPick(argc, argv, 1, tier, &state)) {
        return CLI_INVALID_ARGS;
    }

    // Nothing on the Ceph side to tear down, so this is the registry entry and
    // the backend generated from it -- which is the whole problem with that
    // state: Cinder advertises a volume type whose pool does not exist. The
    // Ceph-side delete would refuse here, because it cannot read the members of
    // a class that is not there.
    //
    // TIER_REGISTRY_PARTIAL deliberately does NOT come in here, and the state
    // exists to keep it out. This branch tells the operator there is nothing
    // on the Ceph side and then removes only the registry entry, so it has to
    // be reached only when that is known to be true: a tier still holding a
    // class, a rule or a pool would be silently orphaned by it -- objects with
    // no owner and no record. A partial one goes down the full path below,
    // where hex_sdk's delete takes each piece it actually finds.
    if (state == TIER_REGISTRY_ONLY) {
        CliPrintf("\nDevice tier '%s' has nothing on the Ceph side: no device class, CRUSH rule or pool. Only its registry entry and the Cinder backend generated from it will be removed. No data is affected.",
            tier.c_str());
        if (!CliReadConfirmation()) {
            return CLI_SUCCESS;
        }
        if (CephDeviceTierSpawn("cinder_apply_storage_tier_deletion", tier, {})) {
            HexLogError("Failed to unregister device tier %s", tier.c_str());
            CliPrintf("\n--\nFailed to unregister device tier %s.", tier.c_str());
            return CLI_FAILURE;
        }
        CliPrintf("device tier %s unregistered", tier.c_str());
        return CLI_SUCCESS;
    }

    std::vector<CephOsdRow> rows;
    if (!CephDeviceTierOsdTable(rows)) {
        return CLI_FAILURE;
    }

    std::string members;
    for (const auto& r : rows) {
        if (r.cls == tier) {
            members.append(" osd.").append(r.id);
        }
    }

    CliPrintf("\nWarning: ALL DATA IN POOL %s WILL BE LOST!", tier.c_str());
    CliPrintf("The Cinder backend is taken out of service first, so the volume type stops being served before the pool goes; a tier with volumes still on it is refused rather than half deleted.");
    if (members.length()) {
        CliPrintf("Afterwards the OSDs it holds (%s ) are left with no device class -- they are not restored to whatever they carried before this tier.",
            members.c_str());
    }

    if (!CliReadConfirmation()) {
        return CLI_SUCCESS;
    }

    if (CephDeviceTierSpawn("ceph_device_tier_delete", tier, {})) {
        HexLogError("Failed to delete device tier %s", tier.c_str());
        CliPrintf("\n--\nFailed to delete device tier %s.", tier.c_str());
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
CephDeviceTierList(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    if (HexExitStatus(HexSpawn(0, HEX_SDK, "ceph_device_tier_list", NULL))) {
        CliPrintf("Failed to list the device tiers.");
        return CLI_FAILURE;
    }

    return CLI_SUCCESS;
}

static int
CreateRestfulKeyMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="key_create" [1]="name" */)
        return CLI_INVALID_ARGS;

    std::string name;

    if (!CliReadInputStr(argc, argv, 1, "Input username: ", &name) || name.length() <= 0) {
        CliPrint("username is required");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "ceph_restful_key_create", name.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
DeleteRestfulKeyMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="key_delete" [1]="name" */)
        return CLI_INVALID_ARGS;

    int index;
    std::string cmd;
    std::string name;

    cmd = std::string(HEX_SDK) + " ceph_restful_username_list";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, &name, "Select a username: ") != CLI_SUCCESS) {
        CliPrintf("Invalid username");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "ceph_restful_key_delete", name.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
ListRestfulKeyMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="key_list" */)
        return CLI_INVALID_ARGS;

    HexSpawn(0, HEX_SDK, "ceph_restful_key_list", NULL);

    return CLI_SUCCESS;
}

static int
CephMirrorSitePair(int argc, const char** argv)
{
    if (argc > 3) {
        return CLI_INVALID_ARGS;
    }
    std::string strIp;
    struct in_addr v4addr;
    std::string strSecret;

    if (argc > 1)
        strIp = argv[1];

    if (argc > 2)
        strSecret = argv[2];

    if (!strIp.length())
        CliReadLine(LABEL_SITE_IP, strIp);
    if (!HexParseIP(strIp.c_str(), AF_INET, &v4addr)) {
        CliPrintf("Invalid IP address: %s\n", strIp.c_str());
        return false;
    }

    if (!strSecret.length())
        CliReadLine(LABEL_SITE_SECRET, strSecret);

    HexSpawn(0, HEX_SDK, "ceph_mirror_pair", strIp.c_str(), strSecret.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
CephMirrorSiteUnpair(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    if (CliReadConfirmation())
        HexSpawn(0, HEX_SDK, "ceph_mirror_unpair", NULL);

    return CLI_SUCCESS;
}

static int
CephMirrorRuleDisable(int argc, const char** argv)
{
    int volIdx;
    std::string volVal;
    std::string addedVols = HexUtilPOpen(HEX_SDK " ceph_mirror_added_volume_list");
    if (addedVols.length() == 0) {
        CliPrintf("no volume to disable");
        return CLI_SUCCESS;
    }

    if ((argc == 2 && std::string(argv[1]) == "?") || (argc == 2 && std::string(argv[1]) == "help")) {
        return CLI_INVALID_ARGS;
    } else if (argc == 2 && std::string(argv[1]) == "all") {
        HexSpawn(0, HEX_SDK, "-v", "ceph_mirror_added_volume_list", NULL);

        if (CliReadConfirmation()) {
            HexSpawn(0, HEX_SDK, "ceph_mirror_image_disable", addedVols.c_str(), NULL);
        }
    } else if (argc < 3) {
        std::string optCmd = std::string(HEX_SDK) + " ceph_mirror_added_volume_list";
        std::string descCmd = std::string(HEX_SDK) + " -v ceph_mirror_added_volume_list";
        if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &volIdx, &volVal, "Select volume: ") != CLI_SUCCESS) {
            CliPrintf("Invalid volume");
            return false;
        }
        HexSpawn(0, HEX_SDK, "ceph_mirror_image_disable", volVal.c_str(), NULL);
    } else {
        for (int i = 1; i < argc; i++) {
            volVal += argv[i];
            if (i < argc - 1) {
                volVal += " ";
            }
        }
        HexSpawn(0, HEX_SDK, "ceph_mirror_image_disable", volVal.c_str(), NULL);
    }

    return CLI_SUCCESS;
}

static int
CephMirrorRuleEnableSnapshot(int argc, const char** argv)
{
    std::string mirrorMode = "snapshot";
    const char* label_snapshot_interval = "Press enter to continue with default 15m or provide snapshot interval (ex: 1d, 2h or 3m): ";
    int volIdx;
    std::string volVal, snapshotInterval;
    std::string availVols = HexUtilPOpen(HEX_SDK " ceph_mirror_avail_volume_list");
    if (availVols.length() == 0) {
        CliPrintf("no volume to enabel");
        return CLI_SUCCESS;
    }

    if (!CliReadInputStr(0, NULL, 0, label_snapshot_interval, &snapshotInterval) || snapshotInterval.length() == 0) {
        snapshotInterval = "15m";
    }

    if ((argc == 2 && std::string(argv[1]) == "?") || (argc == 2 && std::string(argv[1]) == "help")) {
        return CLI_INVALID_ARGS;
    } else if (argc == 2 && std::string(argv[1]) == "all") {
        HexSpawn(0, HEX_SDK, "-v", "ceph_mirror_avail_volume_list", NULL);

        if (CliReadConfirmation()) {
            HexSpawn(0, HEX_SDK, "ceph_mirror_image_enable", mirrorMode.c_str(), snapshotInterval.c_str(), availVols.c_str(), NULL);
        }
    } else if (argc < 3) {
        std::string optCmd = std::string(HEX_SDK) + " ceph_mirror_avail_volume_list";
        std::string descCmd = std::string(HEX_SDK) + " -v ceph_mirror_avail_volume_list";
        if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &volIdx, &volVal, "Select volume: ") != CLI_SUCCESS) {
            CliPrintf("Invalid volume");
            return false;
        }
        HexSpawn(0, HEX_SDK, "ceph_mirror_image_enable", mirrorMode.c_str(), snapshotInterval.c_str(), volVal.c_str(), NULL);
    } else {
        for (int i = 1; i < argc; i++) {
            volVal += argv[i];
            if (i < argc - 1) {
                volVal += " ";
            }
        }
        HexSpawn(0, HEX_SDK, "ceph_mirror_image_enable", mirrorMode.c_str(), snapshotInterval.c_str(), volVal.c_str(), NULL);
    }

    return CLI_SUCCESS;
}

static int
CephMirrorRuleEnableJournal(int argc, const char** argv)
{
    std::string mirrorMode = "journal";
    int volIdx;
    std::string volVal;
    std::string availVols = HexUtilPOpen(HEX_SDK " ceph_mirror_avail_volume_list");
    if (availVols.length() == 0) {
        CliPrintf("no available volume detected");
        return CLI_SUCCESS;
    }

    if ((argc == 2 && std::string(argv[1]) == "?") || (argc == 2 && std::string(argv[1]) == "help")) {
        return CLI_INVALID_ARGS;
    } else if (argc == 2 && std::string(argv[1]) == "all") {
        HexSpawn(0, HEX_SDK, "-v", "ceph_mirror_avail_volume_list", NULL);

        if (CliReadConfirmation()) {
            HexSpawn(0, HEX_SDK, "ceph_mirror_image_enable", mirrorMode.c_str(), availVols.c_str(), NULL);
        }
    } else if (argc < 3) {
        std::string optCmd = std::string(HEX_SDK) + " ceph_mirror_avail_volume_list";
        std::string descCmd = std::string(HEX_SDK) + " -v ceph_mirror_avail_volume_list";
        if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &volIdx, &volVal, "Select volume: ") != CLI_SUCCESS) {
            CliPrintf("Invalid volume");
            return false;
        }
        HexSpawn(0, HEX_SDK, "ceph_mirror_image_enable", mirrorMode.c_str(), volVal.c_str(), NULL);
    } else {
        for (int i = 1; i < argc; i++) {
            volVal += argv[i];
            if (i < argc - 1) {
                volVal += " ";
            }
        }
        HexSpawn(0, HEX_SDK, "ceph_mirror_image_enable", mirrorMode.c_str(), volVal.c_str(), NULL);
    }

    return CLI_SUCCESS;
}

static int
CephMirrorStatus(int argc, const char** argv)
{
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    if (argc == 2 && strncmp(argv[1], "watch", 5) == 0)
        HexSpawn(0, "/usr/bin/watch", "-n", "10", "-t", HEX_SDK, "ceph_mirror_status", NULL);
    else
        HexSpawn(0, HEX_SDK, "ceph_mirror_status", NULL);

    return CLI_SUCCESS;
}

static int
CephMirrorPromote(int argc, const char** argv)
{
    if (argc > 4) {
        return CLI_INVALID_ARGS;
    }

    CliList type, mode;
    int typeIdx, modeIdx;
    std::string typeVal, modeVal;

    type.push_back("normal");
    type.push_back("force");

    if (CliMatchListHelper(argc, argv, 1, type, &typeIdx, &typeVal) != 0) {
        CliPrintf("Unknown type");
        return CLI_INVALID_ARGS;
    }

    mode.push_back("site");
    mode.push_back("volume");

    if (CliMatchListHelper(argc, argv, 2, mode, &modeIdx, &modeVal) != 0) {
        CliPrintf("Unknown mode");
        return CLI_INVALID_ARGS;
    }

    if (modeVal == "volume") {
        int volIdx;
        std::string volVal;

        std::string cmd = HEX_SDK " -v ceph_mirror_image_list cinder-volumes demoted";
        if (CliMatchCmdHelper(argc, argv, 3, cmd, &volIdx, &volVal, "Select volume: ") != CLI_SUCCESS) {
            CliPrintf("Invalid volume");
            return false;
        }

        HexSpawn(0, HEX_SDK, "ceph_mirror_promote_image", volVal.c_str(), typeVal.c_str(), NULL);
    } else if (modeVal == "site") {
        HexSpawn(0, HEX_SDK, "ceph_mirror_promote_site", typeVal.c_str(), NULL);
    }

    return CLI_SUCCESS;
}

static int
CephMirrorInstance(int argc, const char** argv)
{
    if (argc > 3) {
        return CLI_INVALID_ARGS;
    } else if ((argc == 2 && std::string(argv[1]) == "?") || (argc == 2 && std::string(argv[1]) == "help")) {
        return CLI_INVALID_ARGS;
    }

    CliList choice;
    int choiceIdx, insIdx;
    std::string choiceVal, insVal;

    choice.push_back("all");
    choice.push_back("single");

    if (CliMatchListHelper(argc, argv, 1, choice, &choiceIdx, &choiceVal) != 0) {
        CliPrintf("Unknown choice");
        return CLI_INVALID_ARGS;
    }

    if (choiceVal == "all") {
        insVal = HexUtilPOpen(HEX_SDK " ceph_mirror_promoted_instance_list");
        if (insVal.length() == 0) {
            CliPrintf("no instance to create and launch");
            return false;
        }
        HexSpawn(0, HEX_SDK, "-v", "ceph_mirror_promoted_instance_list", NULL);
        if (CliReadConfirmation()) {
            HexSpawn(0, HEX_SDK, "ceph_mirror_create_server", insVal.c_str(), NULL);
        }
    } else {
        std::string optCmd = std::string(HEX_SDK) + " ceph_mirror_promoted_instance_list";
        std::string descCmd = std::string(HEX_SDK) + " -v ceph_mirror_promoted_instance_list";
        if (CliMatchCmdDescHelper(argc, argv, 2, optCmd, descCmd, &insIdx, &insVal, "Select instance: ") != CLI_SUCCESS) {
            CliPrintf("Invalid instance");
            return false;
        }
        HexSpawn(0, HEX_SDK, "ceph_mirror_create_server", insVal.c_str(), NULL);
    }

    return CLI_SUCCESS;
}

static int
CephMirrorRestart(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "ceph_mirror_restart", NULL);

    return CLI_SUCCESS;
}

// This mode is not available in STRICT error state
CLI_MODE(CLI_TOP_MODE, "storage",
    "Work with storage settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("storage", "status", CephStatusMain, NULL,
    "Show storage status.",
    "status [details]");

CLI_MODE_COMMAND("storage", "set_autoscale", CephAutoScaleMain, NULL,
    "Turn on/off pool autoscaling.",
    "set_pool_autoscale [on|off]");

CLI_MODE_COMMAND(
    "storage",
    "set_force_use_mpath_devices",
    CephSetForceUseMpathDevicesMain,
    NULL,
    "Set to allow multipath devices be added to Ceph even if external storage is set under iaas > volume_backend.",
    "set_force_use_mpath_devices [true|false]");

CLI_MODE_COMMAND("storage", "list_avail", CephListAvailDisksMain, NULL,
    "List all available disks recognized by this node.",
    "list_avail");

CLI_MODE_COMMAND("storage", "add_avail", CephAddAvailDisksMain, NULL,
    "Add all available disks recognized by this node.",
    "add_avail <[raw|encrypt]>");

CLI_MODE_COMMAND("storage", "add_disk", CephAddDiskMain, NULL,
    "Add a disk recognized by this node.",
    "add_disk <[/dev/sdx]> <[raw|encrypt]>");

CLI_MODE_COMMAND("storage", "remove_disk", CephRemoveDiskMain, NULL,
    "Remove a disk with safe or force mode from this node.",
    "remove_disk <[/dev/sdx]> <[safe|force]>");

CLI_MODE_COMMAND("storage", "remove_exist", CephRemoveExistMain, NULL,
    "Remove all existing disks from this node.",
    "remove_exist <[safe|force]>");

CLI_MODE_COMMAND("storage", "list_osd", CephListOsdMain, NULL,
    "List all osds and examine the selected one for health details.",
    "remove_osd [<osd.id>]");

CLI_MODE_COMMAND("storage", "remove_osd", CephRemoveOsdMain, NULL,
    "Remove an osd from cluster.",
    "remove_osd [<osd.id>]");

CLI_MODE_COMMAND("storage", "rebalance", CephRebalanceMain, NULL,
    "Re-balance page groups or adjust replication size.",
    "rebalance [<replication size>]");

CLI_MODE_COMMAND("storage", "sync_config", CephConfigSyncMain, NULL,
    "Sync storage config when monitor cluster topology is changed.",
    "sync_config");

CLI_MODE_COMMAND("storage", "maintenance", CephMaintenanceMain, NULL,
    "Turn on/off storage maintenance mode to avoid data migrations.",
    "maintenance [on|off|status]");

CLI_MODE_COMMAND("storage", "add_group", CephCreateNodeGroup, NULL,
    "Add a new group whose backend and cache pools map to osd devices of corresponding nodes.",
    "add_group group node [<node2...>]");

CLI_MODE_COMMAND("storage", "remove_group", CephRemoveNodeGroup, NULL,
    "Remove a group and reassign corresponding nodes back to default bucket.",
    "remove_group group");

CLI_MODE_COMMAND("storage", "list_group", CephNodeGroupList, NULL,
    "List existing ceph groups and the associated nodes.",
    "list_group");

CLI_MODE_COMMAND("storage", "promote_disk", CephPromoteDiskToCache, NULL,
    "Promote a (fast) disk to cache-tier or ssdpool.",
    "promote_disk");

CLI_MODE_COMMAND("storage", "demote_disk", CephDemoteDiskToCache, NULL,
    "Demote a (fast) disk from cache-tier or ssdpool.",
    "demote_disk");

CLI_MODE_COMMAND("storage", "add_ssdpool", CephCreateSsdPool, NULL,
    "Add SSD pool (block device volume) to specified group.",
    "add_ssdpool group");

CLI_MODE_COMMAND("storage", "remove_ssdpool", CephRemoveSsdPool, NULL,
    "Remove SSD pool of specified group.",
    "remove_ssdpool group");

CLI_MODE("storage", "tier",
    "Work with storage device tiers: named sets of OSDs, each with its own CRUSH device class, pool and Cinder volume type. Not the same thing as cache tiering, which lives under storage > cache.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("tier", "create", CephDeviceTierCreate, NULL,
    "Create a device tier over a set of OSDs and a Cinder volume type for it.",
    "create <tier> <osd id> [<osd id>...]");

CLI_MODE_COMMAND("tier", "update", CephDeviceTierUpdate, NULL,
    "Change which OSDs a device tier consists of.",
    "update <tier> <osd id> [<osd id>...]");

CLI_MODE_COMMAND("tier", "delete", CephDeviceTierDelete, NULL,
    "Delete a device tier, its pool and its Cinder volume type.",
    "delete <tier>");

CLI_MODE_COMMAND("tier", "list", CephDeviceTierList, NULL,
    "List the device tiers and where the registry and Ceph disagree.",
    "list");

CLI_MODE("storage", "restful",
    "Work with stroage restful API settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("restful", "key_create", CreateRestfulKeyMain, NULL,
    "Create a restful API for a given name.",
    "key_create [<name>]");

CLI_MODE_COMMAND("restful", "key_delete", DeleteRestfulKeyMain, NULL,
    "Delete a restful API for a given name.",
    "key_delete [<name>]");

CLI_MODE_COMMAND("restful", "key_list", ListRestfulKeyMain, NULL,
    "List all restful API keys.",
    "key_list");

// This mode is not available in STRICT error state
CLI_MODE("storage", "mirror",
    "Work with block device (volume) data protection settings and rules.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE("mirror", "site",
    "Configure mirror sites (primary and peer).",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("site", "pair", CephMirrorSitePair, NULL,
    "Pair up local and peer sites with volume mirroring.",
    "pair peerVip peerPasswd");

CLI_MODE_COMMAND("site", "unpair", CephMirrorSiteUnpair, NULL,
    "Unpair local and peer sites.",
    "unpair");

CLI_MODE("mirror", "rule",
    "Work with block device (volume) data protection rules.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE("rule", "enable",
    "Enable volume mirror rule(s) on local site.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("enable", "snapshot", CephMirrorRuleEnableSnapshot, NULL,
    "Enable volume mirror rule(s) with snapshot mode.",
    "snapshot [all|volumeId(s)]");

CLI_MODE_COMMAND("enable", "journal", CephMirrorRuleEnableJournal, NULL,
    "Enable volume mirror rule(s) with journal mode.",
    "journal [all|volumeId(s)]");

CLI_MODE_COMMAND("rule", "disable", CephMirrorRuleDisable, NULL,
    "Disable volume mirror rule(s) on local site.",
    "disable [all|volumeId(s)]");

CLI_MODE_COMMAND("mirror", "status", CephMirrorStatus, NULL,
    "Get the volumes/pools mirroring status.",
    "status [watch]");

CLI_MODE_COMMAND("mirror", "promote", CephMirrorPromote, NULL,
    "Promote the storage cluster as primary cluster.",
    "promote [normal|force] [site|volume]");

CLI_MODE_COMMAND("mirror", "instance", CephMirrorInstance, NULL,
    "Create and launch servers whose volumes were promoted on peer cluster.",
    "instance [all|single]");

CLI_MODE_COMMAND("mirror", "restart", CephMirrorRestart, NULL,
    "Restart mirroring process in case of unstable or unsynced.",
    "restart");

// Cache Tier related commands
CLI_MODE("storage", "cache",
    "Work with fast storage to store hot data.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("cache", "status", CephShowCache, NULL,
    "Display cache status.",
    "status <backpool>");

CLI_MODE_COMMAND("cache", "switch", CephSwitchCache, NULL,
    "Switch on/off of the cache.",
    "switch backpool <[on|off]>");

CLI_MODE_COMMAND("cache", "set_profile", CephCacheProfileSet, NULL,
    "Adjust cache profile.",
    "set_profile backpool <[high-burst|default|low-burst]>");

CLI_MODE_COMMAND("cache", "flush", CephCacheFlush, NULL,
    "Flush data back to the base tier.",
    "flush backpool");
