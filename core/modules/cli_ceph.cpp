// HEX SDK

#include <unistd.h>

#include <vector>
#include <string>

#include <hex/log.h>
#include <hex/strict.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/string_util.h>
#include <hex/yml_util.h>
#include <hex/cli_util.h>
#include <hex/cli_module.h>

#include <cube/cubesys.h>

#include <sys/socket.h>
#include <netinet/in.h>

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
        HexSystemF(0, "cubectl node exec -pn hex_sdk -v ceph_osd_list %s", osdId.c_str());
    } else {
        printf(LIST_OSD_FMT, "OSD", "STATE", "HOST", "DEV", "SERIAL", "POWER_ON", "USE", "REMARK");
        HexSystemF(0, "cubectl node exec -pn hex_sdk ceph_osd_list | sort -k3");
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
    if (argc == 2){
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
    if (argc == 3){
        backPool = argv[1];
        input = argv[2];
    } else if (argc == 2){
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
    if (argc == 3){
        backPool = argv[1];
        profile = argv[2];
    } else if (argc == 2){
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
        if (d.length() < 8) continue;
        std::string typ = HexUtilPOpen(HEX_SDK" ceph_osd_get_class %s", d.c_str());
        // display only non ssd device (e.g.: hdd or nvme)
        if (typ == "ssd") continue;
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
        printf(OSD_FMT, i + 1,  matchedDevs[i].c_str(), sz.c_str(), ids.c_str(), sn.c_str());
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
        if (d.length() < 8) continue;
        std::string typ = HexUtilPOpen(HEX_SDK" ceph_osd_get_class %s", d.c_str());
        // display only ssd device
        if (typ != "ssd") continue;
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
    if (argc == 2){
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
    }
    else {
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

    switch(index) {
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
CephListAvailDisksMain(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    std::string alldev = HexUtilPOpen(HEX_SDK " ListAvailDisks");
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
        if (mode != "encrypt")
            mode = "raw";
    }

    // 1. List avail disks
    std::string alldev = HexUtilPOpen(HEX_SDK " ListAvailDisks");
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
        if (CliMatchCmdHelper(argc, argv, 2, "echo -e 'raw\nencrypt'", &index, &mode, "Disk protection mode:") != CLI_SUCCESS)
            return CLI_INVALID_ARGS;

        if (mode == "encrypt")
            CliPrintf("Encrypt disk(s) to protect physical disk loss (beware of performance impacts).");
        else if (mode == "raw")
            CliPrintf("No disk encryption (default mode).");
        else
            return CLI_SUCCESS;

        if (!CliReadConfirmation())
            return CLI_SUCCESS;
    }

    // 3. Add this OSD
    cnt = 0;
    printf(DISK_F_FMT);
    for (auto& d : allDevs) {
        if (HexSystemF(0, HEX_SDK " ceph_osd_add_disk_%s %s", mode.c_str(), d.c_str()) != 0) {
            CliPrintf("Failed to add disk(%s) %s.", mode.c_str(), d.c_str());
        } else {
            CliPrintf("Added disk(%s) %s.", mode.c_str(), d.c_str());
        }
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
        // any user input mode which is not "force" falls back to "safe" mode
        mode = argv[2];
        if (mode != "encrypt")
            mode = "raw";
    } else if (argc == 2) {
        device = argv[1];
    }

    if (device.empty()) {
        // 1. List avail disks
        std::string alldev = HexUtilPOpen(HEX_SDK " ListAvailDisks");
        if (alldev.length() < 8 /* start with /dev/sdx */) {
            CliPrintf("No available disk.");
            return CLI_SUCCESS;
        }

        std::vector<std::string> allDevs = hex_string_util::split(alldev, ' ');
        uint32_t cnt = 0;

        // 1.b) display candidates
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
        device = allDevs[index - 1];

        int idx;
        if (CliMatchCmdHelper(argc, argv, 2, "echo -e 'raw\nencrypt'", &idx, &mode, "Disk protection mode:") != CLI_SUCCESS)
            return CLI_INVALID_ARGS;

        if (mode == "encrypt")
            CliPrintf("Encrypt disk(s) to protect physical disk loss (beware of performance impacts).");
        else if (mode == "raw")
            CliPrintf("No disk encryption (default mode).");
        else
            return CLI_SUCCESS;

        if (!CliReadConfirmation())
            return CLI_SUCCESS;
    }
    // 3. Add this OSD
    if (HexSystemF(0, HEX_SDK " ceph_osd_add_disk_%s %s", mode.c_str(), device.c_str()) != 0) {
        CliPrintf("Failed to add disk(%s) %s.", mode.c_str(), device.c_str());
    } else {
        CliPrintf("Added disk(%s) %s.", mode.c_str(), device.c_str());
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
        size_t cnt = allDevs.size();
        if (!cnt) {
            CliPrintf("No disk to be removed.");
            return CLI_SUCCESS;
        }

        // 1.b) display candidates
        printf(OSD_H_FMT, "index", "name", "size", "osd", "serial");
        for (size_t i = 0; i < cnt; i++) {
            std::string sz = HexUtilPOpen("echo -n $(lsblk -n -d -o SIZE %s)", allDevs[i].c_str());
            std::string ids = HexUtilPOpen(HEX_SDK " ceph_get_ids_by_dev %s", allDevs[i].c_str());
            std::string sn = HexUtilPOpen(HEX_SDK " ceph_get_sn_by_dev %s", allDevs[i].c_str());
            printf(OSD_FMT, i + 1, allDevs[i].c_str(), sz.c_str(), ids.c_str(), sn.c_str());
        }
        printf(OSD_F_FMT);

        // 2. User input
        std::string input;
        size_t index = 0;
        CliReadLine("Enter the index of disk to be removed: ", input);
        if (!HexParseUInt(input.c_str(), 1, cnt, &index)) {
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
        CliPrintf("Removed disk %s.", device.c_str());


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
    size_t cnt = allDevs.size();
    if (!cnt) {
        CliPrintf("No disk to be removed.");
        return CLI_SUCCESS;
    }

    // 1.b) display candidates
    printf(OSD_H_FMT, "index", "name", "size", "osd", "serial");
    for (size_t i = 0; i < cnt; i++) {
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
            CliPrintf("Removed disk %s.", d.c_str());
            cnt++;
        }
    }
    printf(DISK_F_FMT);
    CliPrintf("Processed %u disk%s out of %u.", cnt, (cnt <= 1) ? "" : "s", allDevs.size());

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

    if (!CliReadInputStr(argc, argv, 1, "Input replication factor(1/2/3): ", &rf) ||
        !HexParseInt(rf.c_str(), 1, 3, &size)) {
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

    if(CliMatchListHelper(argc, argv, 1, options, &index, &value) != 0) {
        CliPrintf("Unknown command");
        return CLI_INVALID_ARGS;
    }

    switch(index) {
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
    for (int i=1; i<argc; i++) {
        nodes.append(argv[i]);
        if (i < (argc - 1)) nodes.append(" ");
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

static int
CreateRestfulKeyMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="key_create" [1]="name" */)
        return CLI_INVALID_ARGS;

    std::string name;

    if (!CliReadInputStr(argc, argv, 1, "Input username: ", &name) ||
        name.length() <= 0) {
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
    if(CliMatchCmdHelper(argc, argv, 1, cmd, &index, &name, "Select a username: ") != CLI_SUCCESS) {
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

    if (argc > 1) strIp=argv[1];

    if (argc > 2) strSecret=argv[2];

    if (!strIp.length()) CliReadLine(LABEL_SITE_IP, strIp);
    if (!HexParseIP(strIp.c_str(), AF_INET, &v4addr)) {
        CliPrintf("Invalid IP address: %s\n", strIp.c_str());
        return false;
    }

    if (!strSecret.length()) CliReadLine(LABEL_SITE_SECRET, strSecret);

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
        for (int i=1; i<argc; i++) {
            volVal += argv[i];
            if (i<argc-1) {
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
    std::string  mirrorMode="snapshot";
    const char* label_snapshot_interval = "Press enter to continue with default 15m or provide snapshot interval (ex: 1d, 2h or 3m): ";
    int volIdx;
    std::string volVal, snapshotInterval;
    std::string availVols = HexUtilPOpen(HEX_SDK " ceph_mirror_avail_volume_list");
    if (availVols.length() == 0) {
        CliPrintf("no volume to enabel");
        return CLI_SUCCESS;
    }

    if (!CliReadInputStr(0, NULL, 0, label_snapshot_interval, &snapshotInterval) || snapshotInterval.length() == 0) {
        snapshotInterval="15m";
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
        for (int i=1; i<argc; i++) {
            volVal += argv[i];
            if (i<argc-1) {
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
    std::string  mirrorMode="journal";
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
        for (int i=1; i<argc; i++) {
            volVal += argv[i];
            if (i<argc-1) {
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

    if(CliMatchListHelper(argc, argv, 1, type, &typeIdx, &typeVal) != 0) {
        CliPrintf("Unknown type");
        return CLI_INVALID_ARGS;
    }

    mode.push_back("site");
    mode.push_back("volume");

    if(CliMatchListHelper(argc, argv, 2, mode, &modeIdx, &modeVal) != 0) {
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

    if(CliMatchListHelper(argc, argv, 1, choice, &choiceIdx, &choiceVal) != 0) {
        CliPrintf("Unknown choice");
        return CLI_INVALID_ARGS;
    }

    if (choiceVal == "all") {
        insVal=HexUtilPOpen(HEX_SDK " ceph_mirror_promoted_instance_list");
        if ( insVal.length() == 0) {
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

static int
CephToggleDiskCheckMain(int argc, const char** argv)
{
    if (argc > 1 /* [0]="toggle_diskcheck" */)
        return CLI_INVALID_ARGS;

    std::string status=HexUtilPOpen(HEX_SDK " health_check_toggle_status ceph_disk");
    CliPrintf("Current status: %s", status.c_str());

    if (CliReadConfirmation())
        HexSpawn(0, HEX_SDK, "health_check_toggle ceph_disk", NULL);

    return CLI_SUCCESS;
}

// This mode is not available in STRICT error state
CLI_MODE(CLI_TOP_MODE, "storage",
         "Work with storage settings.",
         !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("storage", "toggle_diskcheck", CephToggleDiskCheckMain, NULL,
                 "Toggle disk check.",
                 "toggle_diskcheck");

CLI_MODE_COMMAND("storage", "status", CephStatusMain, NULL,
                 "Show storage status.",
                 "status [details]");

CLI_MODE_COMMAND("storage", "set_autoscale", CephAutoScaleMain, NULL,
                 "Turn on/off pool autoscaling.",
                 "set_pool_autoscale [on|off]");

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
