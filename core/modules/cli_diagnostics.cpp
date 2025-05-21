// HEX SDK

#include <unistd.h>

#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/log.h>
#include <hex/strict.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

#include <cube/cubesys.h>

static const char* LABEL_IMAGE = "Select an image: ";
static const char* LABEL_EXT_NET = "Select an external (share) network: ";
static const char* LABEL_DOMAIN_NAME = "Specify ping target domain name (ex: www.google.com): ";
static const char* LABEL_NAME_SERVER_IP = "Specify DNS name server IP (ex: 8.8.8.8): ";

static int ArpScanMain(int argc, const char** argv)
{
    CliPrintf("Scanning ARP tables of all operational networks (takes minutes)");
    HexSystemF(0, "cubectl node exec -p hex_sdk diagnostics_arpscan >/dev/null");
    HexSystemF(0, "cubectl node exec hex_sdk diagnostics_arpscan_report");

    return CLI_SUCCESS;
}

static int TestgroundConstructMain(int argc, const char** argv)
{
    if (argc > 4 /* [0]="dns_start", [1]=<external-network>, [2]=<domain-name>, [3]=<name-server-ip> */)
        return CLI_INVALID_ARGS;

    int index = 0;
    std::string extnet, domainname, nameserverip, cmd;

    cmd = HEX_SDK " os_list_public_share_net_by_domain";;
    if(CliMatchCmdHelper(argc, argv, 1, cmd, &index, &extnet, LABEL_EXT_NET) != CLI_SUCCESS) {
        CliPrintf("external network is missing or not shared");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 2, LABEL_DOMAIN_NAME, &domainname) || domainname.length() == 0) {
        domainname = "www.google.com";
        CliPrintf("using default ping target FQDN: www.google.com");
    }

    if (!CliReadInputStr(argc, argv, 3, LABEL_NAME_SERVER_IP, &nameserverip) || nameserverip.length() == 0) {
        nameserverip = HexUtilPOpen("cat /etc/resolv.conf | grep nameserver | head -1 | cut -d' ' -f2");
        CliPrintf("using host DNS name server IP: %s", nameserverip.c_str());
    }

    HexSpawn(0, HEX_SDK, "diagnostics_network", extnet.c_str(), domainname.c_str(), nameserverip.c_str(), NULL);

    return CLI_SUCCESS;
}

static int TestgroundDestructMain(int argc, const char** argv)
{
    HexSpawn(0, HEX_SDK, "diagnostics_teardown", NULL);

    return CLI_SUCCESS;
}

static int ServerLaunchMain(int argc, const char** argv)
{
    if (argc > 5 /* [0]="launch", [1]=<image-name>, [2]=<external-network>, [3]=<cinder-volumes|ephemeral-vms> [4]=<num-per-compute> */)
        return CLI_INVALID_ARGS;

    int index = 0;
    std::string cmd;
    std::string image="Cirros";
    std::string extnet="public";
    std::string backPool="cinder-volumes";
    int numPerCompute=1;

    if (argc == 5) {
        image = argv[1];
        extnet = argv[2];
        backPool = argv[3];
        numPerCompute = std::atoi(argv[4]);
    } else if (argc == 4) {
        image = argv[1];
        extnet = argv[2];
        backPool = argv[3];
    } else if (argc == 3) {
        image = argv[1];
        extnet = argv[2];
    } else if (argc == 2) {
        image = argv[1];
    } else {
        cmd = HEX_SDK " os_list_image | grep -o Cirros";; // FIXME: only Cirros is currently supported
        if(CliMatchCmdHelper(argc, argv, 1, cmd, &index, &image, LABEL_IMAGE) != CLI_SUCCESS) {
            CliPrintf("Image is missing or not bootable");
            return CLI_INVALID_ARGS;
        }

        cmd = HEX_SDK " os_list_public_share_net_by_domain";;
        if(CliMatchCmdHelper(argc, argv, 1, cmd, &index, &extnet, LABEL_EXT_NET) != CLI_SUCCESS) {
            CliPrintf("external network is missing or not shared");
            return CLI_INVALID_ARGS;
        }

        std::string optCmd = "printf 'cinder-volumes\nephemeral-vms\n'";
        std::string descCmd = "printf 'cinder-volumes (boot from volume)\nephemeral-vms (boot from image)\n'";
        if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &backPool, "Enter index of back pool where servers will be created: ") != CLI_SUCCESS) {
            CliPrintf("Bad pool or invalid index chosen");
            return CLI_SUCCESS;
        }
    }

    HexSystemF(0, HEX_SDK " _diagSrvCreate %s %s %s %d", image.c_str(), extnet.c_str(), backPool.c_str(), numPerCompute);

    return CLI_SUCCESS;
}

static int ServerDeleteallMain(int argc, const char** argv)
{
    HexSpawn(0, HEX_SDK, "_diagSrvDelete", NULL);

    return CLI_SUCCESS;
}

static int PoolMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="pool" [1]="pool" [2]="<time(Seconds)>" */) {
        return CLI_INVALID_ARGS;
    }

    std::string backPool;
    int TotalTime = 10; // seconds
    if (argc == 3) {
        backPool = argv[1];
        TotalTime = std::atoi(argv[2]);
    } else if (argc == 2) {
        backPool = argv[1];
    } else {
        int index;
        std::string optCmd = std::string(HEX_SDK) + " ceph_cacheable_backpool_list";
        std::string descCmd = std::string(HEX_SDK) + " -v ceph_cacheable_backpool_list";
        if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &backPool, "Enter index of back pool to check its cache status: ") != CLI_SUCCESS) {
            CliPrintf("No cache tier available or invalid index chosen");
            return CLI_SUCCESS;
        }
    }

    if (TotalTime < 1 || TotalTime > 150) {
        CliPrintf("Test duration %d in seconds have to be within ranage >1 and <150", TotalTime);
        return CLI_UNEXPECTED_ERROR;
    }
    // handle one liner case when backPool does not exist. ex: status nosuchpool
    std::string validBackPool = HexUtilPOpen(HEX_SDK " ceph_get_pool_in_cacheable_backpool %s", backPool.c_str());
    if (validBackPool.empty()) {
        CliPrintf("Pool %s either does not support cache tiering or does not exist", backPool.c_str());
        return CLI_UNEXPECTED_ERROR;
    }

    HexSystemF(0, "/usr/bin/rados -p %s bench --object-size 4096 %d write --no-cleanup", backPool.c_str(), TotalTime);
    HexSystemF(0, "/usr/bin/rados -p %s bench %d rand --no-cleanup", backPool.c_str(), TotalTime);
    return CLI_SUCCESS;
}

static int PoolCleanupMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="pool" [1]="pool" */) {
        return CLI_INVALID_ARGS;
    }

    std::string backPool;
    if (argc == 2) {
        backPool = argv[1];
    } else {
        int index;
        std::string optCmd = std::string(HEX_SDK) + " ceph_cacheable_backpool_list";
        std::string descCmd = std::string(HEX_SDK) + " -v ceph_cacheable_backpool_list";
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

    HexSystemF(0, "/usr/bin/rados -p %s cleanup 2>/dev/null", backPool.c_str());

    return CLI_SUCCESS;
}

static int RbdMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="rbd" [1]="pool" [2]="<size(GB)>" */) {
        return CLI_INVALID_ARGS;
    }

    std::string backPool;
    int TotalData = 1; // 1GB worth of data
    if (argc == 3) {
        backPool = argv[1];
        TotalData = std::atoi(argv[2]);
    } else if (argc == 2) {
        backPool = argv[1];
    } else {
        int index;
        std::string optCmd = std::string(HEX_SDK) + " ceph_cacheable_backpool_list";
        std::string descCmd = std::string(HEX_SDK) + " -v ceph_cacheable_backpool_list";
        if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &backPool, "Enter index of back pool to check its cache status: ") != CLI_SUCCESS) {
            CliPrintf("No cache tier available or invalid index chosen");
            return CLI_SUCCESS;
        }
    }

    if (TotalData < 1 || TotalData > 150) {
        CliPrintf("Test data size %d in GB have to be within ranage >1 and <150", TotalData);
        return CLI_UNEXPECTED_ERROR;
    }
    // handle one liner case when backPool does not exist. ex: status nosuchpool
    std::string validBackPool = HexUtilPOpen(HEX_SDK " ceph_get_pool_in_cacheable_backpool %s", backPool.c_str());
    if (validBackPool.empty()) {
        CliPrintf("Pool %s either does not support cache tiering or does not exist", backPool.c_str());
        return CLI_UNEXPECTED_ERROR;
    }

    HexSystemF(0, HEX_SDK " diagnostics_rbd %s write %d", backPool.c_str(), TotalData);
    HexSystemF(0, HEX_SDK " diagnostics_rbd %s read %d", backPool.c_str(), TotalData);
    return CLI_SUCCESS;
}

static int OsdMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="osd" [1]="osd.id */) {
        return CLI_INVALID_ARGS;
    }

    std::string osdId;
    if (argc == 2) {
        osdId = argv[1];
    } else {
        int index;
        std::string optCmd = "cubectl node exec \"ceph osd ls-tree \\$HOSTNAME 2>/dev/null || true\"";
        std::string descCmd = "cubectl node exec -pn hex_sdk ceph_osd_list | sort -k3";
        if (CliMatchCmdDescHelper(argc, argv, 1, optCmd, descCmd, &index, &osdId, "Enter index of back pool to check its cache status: ") != CLI_SUCCESS) {
            CliPrintf("No cache tier available or invalid index chosen");
            return CLI_SUCCESS;
        }
    }

    HexSystemF(0, "ceph osd df osd.%s | head -2", osdId.c_str());
    HexSystemF(0, "ceph tell osd.%s bench 1073741824 4906", osdId.c_str());
    HexSystemF(0, "cubectl node exec -pn hex_sdk diagnostics_osd_hdparm osd.%s", osdId.c_str());
    return CLI_SUCCESS;
}

static int DdMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="dd" [1]="<size(GB)>" */) {
        return CLI_INVALID_ARGS;
    }

    int TotalData = 10; // 10GB worth of data
    if (argc == 2) {
        TotalData = std::atoi(argv[1]);
    }

    if (TotalData < 1 || TotalData > 150) {
        CliPrintf("Test data size %d in GB have to be within ranage >1 and <150", TotalData);
        return CLI_UNEXPECTED_ERROR;
    }

    CliPrintf("Simultaneously dd %d GB file on each of the following servers", TotalData);
    HexSpawn(0, HEX_SDK, "_diagnostics_server_list", NULL);
    HexSystemF(0, HEX_SDK " _diagnostics_instance_dd %d", TotalData);
    return CLI_SUCCESS;
}

// diagnostics
CLI_MODE(CLI_TOP_MODE, "diagnostics", "Cluster self-diagnosing utilities.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

// diagnostics arp
CLI_MODE_COMMAND("diagnostics", "arpscan", ArpScanMain, NULL,
    "Scan arp tables of all CubeCOS operational networks and report IP conflicts if any.",
    "arpscan");

// diagnostics testground
CLI_MODE("diagnostics", "testground",
    "Work with network operations in _diagnostics project.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("testground", "construct", TestgroundConstructMain, NULL,
    "Construct a test greound and run basic network tests in _diagnostics project.",
    "construct <external-network> <domain-name> <name-server-ip>");

CLI_MODE_COMMAND("testground", "destruct", TestgroundDestructMain, NULL,
    "Destruct everything within _diagnostics project, including networks, servers, volumes and flavors.",
    "destruct");

// diagnostics server
CLI_MODE("diagnostics", "server",
    "Work with server operations in _diagnostics project.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("server", "launch", ServerLaunchMain, NULL,
    "Launch specified number of servers on each compute node in _diagnostics projects.",
    "launch <image-name> <external-server> <cinder-volumes|ephemeral-vms> <num-per-compute>");

CLI_MODE_COMMAND("server", "deleteall", ServerDeleteallMain, NULL,
    "Delete all test servers in _diagnostics project, including voluems.",
    "deleteall");

// diagnostics perf
CLI_MODE("diagnostics", "perf",
    "Work with storage performance tests/benchmarks.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

// diagnostics perf pool
CLI_MODE_COMMAND("perf", "pool", PoolMain, NULL,
    "(storage) pool bench write/read test.",
    "pool pool <time(Seconds)>");

// diagnostics perf cleanup
CLI_MODE_COMMAND("perf", "cleanup", PoolCleanupMain, NULL,
    "(storage) pool cleanup test data.",
    "cleanup pool");

// diagnostics rbd
CLI_MODE_COMMAND("perf", "rbd", RbdMain, NULL,
    "(storage) rbd bench write/read test.",
    "rbd pool <size(GB)>");

// diagnostics osd
CLI_MODE_COMMAND("perf", "osd", OsdMain, NULL,
    "(storage) osd bench write/read test.",
    "osd osd.id");

// diagnostics instance
CLI_MODE_COMMAND("perf", "dd", DdMain, NULL,
    "(storage) dd write a (default 10GB) file on all servers in _diagnostics.",
    "dd <size(GB)>");
