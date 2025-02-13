// HEX SDK

#include <unistd.h>

#include <hex/log.h>
#include <hex/tuning.h>
#include <hex/string_util.h>
#include <hex/process.h>
#include <hex/process_util.h>

#include <hex/config_module.h>
#include <hex/config_tuning.h>
#include <hex/config_global.h>

#include <cube/network.h>
#include <cube/cluster.h>

#include "include/role_cubesys.h"

#define LIMIT   15
#define TIME    3
#define HEX_DONE "/run/bootstrap_done"

static bool s_bNetModified = false;
static bool s_bCubeModified = false;

static CubeRole_e s_eCubeRole;

static ConfigString s_hostname;

static const char CONFIGURED_FILE[] = "/etc/appliance/state/configured";

// declare global variables
CONFIG_GLOBAL_BOOL(IS_MASTER)(false);
CONFIG_GLOBAL_STR(MGMT_IF)("");
CONFIG_GLOBAL_STR(MGMT_ADDR)("0.0.0.0");
CONFIG_GLOBAL_STR(MGMT_CIDR)("0.0.0.0/0");

CONFIG_GLOBAL_STR(PROVIDER_IF)("");

CONFIG_GLOBAL_STR(OVERLAY_IF)("");
CONFIG_GLOBAL_STR(OVERLAY_ADDR)("0.0.0.0");
CONFIG_GLOBAL_STR(OVERLAY_CIDR)("0.0.0.0/0");

CONFIG_GLOBAL_STR(STORAGE_F_IF)("");
CONFIG_GLOBAL_STR(STORAGE_F_ADDR)("0.0.0.0");
CONFIG_GLOBAL_STR(STORAGE_F_CIDR)("0.0.0.0/0");

CONFIG_GLOBAL_STR(STORAGE_B_IF)("");
CONFIG_GLOBAL_STR(STORAGE_B_ADDR)("0.0.0.0");
CONFIG_GLOBAL_STR(STORAGE_B_CIDR)("0.0.0.0/0");

CONFIG_GLOBAL_STR(CTRL)("");
CONFIG_GLOBAL_STR(CTRL_IP)("0.0.0.0");
CONFIG_GLOBAL_STR(SHARED_ID)("0.0.0.0");
CONFIG_GLOBAL_STR(EXTERNAL)("");

// using external tunings
CONFIG_TUNING_SPEC(NET_HOSTNAME);
CONFIG_TUNING_SPEC_STR(CUBESYS_ROLE);
CONFIG_TUNING_SPEC_STR(CUBESYS_DOMAIN);
CONFIG_TUNING_SPEC_STR(CUBESYS_REGION);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROLLER);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROLLER_IP);
CONFIG_TUNING_SPEC_STR(CUBESYS_EXTERNAL);
CONFIG_TUNING_SPEC_STR(CUBESYS_MGMT);
CONFIG_TUNING_SPEC_STR(CUBESYS_PROVIDER);
CONFIG_TUNING_SPEC_STR(CUBESYS_OVERLAY);
CONFIG_TUNING_SPEC_STR(CUBESYS_STORAGE);
CONFIG_TUNING_SPEC_STR(CUBESYS_SEED);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_HOSTS);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_ADDRS);
CONFIG_TUNING_SPEC_STR(CUBESYS_STORAGE_HOSTS);
CONFIG_TUNING_SPEC_STR(CUBESYS_STORAGE_ADDRS);
CONFIG_TUNING_SPEC_STR(CUBESYS_CONTROL_VIP);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_HA);
CONFIG_TUNING_SPEC_BOOL(CUBESYS_SALTKEY);
CONFIG_TUNING_SPEC_INT(CUBESYS_LOG_DEFAULT_RP);
CONFIG_TUNING_SPEC_INT(CUBESYS_CONNTABLE_MAX);

// parse tunings
PARSE_TUNING_X_STR(s_cubeRole, CUBESYS_ROLE, 1);
PARSE_TUNING_X_STR(s_cubeDomain, CUBESYS_DOMAIN, 1);
PARSE_TUNING_X_STR(s_cubeRegion, CUBESYS_REGION, 1);
PARSE_TUNING_X_STR(s_controller, CUBESYS_CONTROLLER, 1);
PARSE_TUNING_X_STR(s_controllerIp, CUBESYS_CONTROLLER_IP, 1);
PARSE_TUNING_X_STR(s_external, CUBESYS_EXTERNAL, 1);
PARSE_TUNING_X_STR(s_mgmt, CUBESYS_MGMT, 1);
PARSE_TUNING_X_STR(s_provider, CUBESYS_PROVIDER, 1);
PARSE_TUNING_X_STR(s_overlay, CUBESYS_OVERLAY, 1);
PARSE_TUNING_X_STR(s_storage, CUBESYS_STORAGE, 1);
PARSE_TUNING_X_STR(s_seed, CUBESYS_SEED, 1);
PARSE_TUNING_X_STR(s_ctrlHosts, CUBESYS_CONTROL_HOSTS, 1);
PARSE_TUNING_X_STR(s_ctrlAddrs, CUBESYS_CONTROL_ADDRS, 1);
PARSE_TUNING_X_STR(s_strgHosts, CUBESYS_STORAGE_HOSTS, 1);
PARSE_TUNING_X_STR(s_strgAddrs, CUBESYS_STORAGE_ADDRS, 1);
PARSE_TUNING_X_STR(s_ctrlVip, CUBESYS_CONTROL_VIP, 1);
PARSE_TUNING_X_BOOL(s_ha, CUBESYS_HA, 1);
PARSE_TUNING_X_BOOL(s_saltKey, CUBESYS_SALTKEY, 1);
PARSE_TUNING_X_INT(s_logDefRp, CUBESYS_LOG_DEFAULT_RP, 1);
PARSE_TUNING_X_INT(s_connMax, CUBESYS_CONNTABLE_MAX, 1);

static std::string
GetIfAddrRetry(const std::string& ifname)
{
    std::string addr = "0.0.0.0";
    int retry = 0;
    while (retry++ < LIMIT) {
        addr = GetIfAddr(ifname);
        if (addr != "0.0.0.0")
            break;
        HexLogWarning("failed to read %s address, retry again", ifname.c_str());
        sleep(TIME);
    }

    return addr;
}

static std::string
GetCIDRv4Retry(const std::string& ifname)
{
    std::string cidr = "0.0.0.0/0";
    int retry = 0;
    while (retry++ < LIMIT) {
        cidr = GetCIDRv4(ifname);
        if (cidr != "0.0.0.0/0")
            break;
        HexLogWarning("failed to read %s CIDR, retry again", ifname.c_str());
        sleep(TIME);
    }

    return cidr;
}

static bool
ParseOld(void)
{
    CubeRole_e r = GetCubeRole(s_cubeRole.oldValue());

    std::string mgmt;
    std::string mgmtIf;
    std::string mgmtAddr;
    std::string mgmtCidr;
    if (IfMgmtReq(r)) {
        mgmt = s_mgmt.oldValue();
        mgmtIf = GetParentIf(mgmt);
        mgmtAddr = GetIfAddrRetry(mgmt);
        mgmtCidr = GetCIDRv4Retry(mgmt);
    }

    std::string provider;
    std::string providerIf;
    if (IfProviderReq(r)) {
        provider = s_provider.oldValue();
        providerIf = provider;
    }

    std::string overlay;
    std::string overlayIf;
    std::string overlayAddr;
    std::string overlayCidr;
    if (IfOverlayReq(r)) {
        overlay = s_overlay.oldValue();
        overlayIf = GetParentIf(overlay);
        overlayAddr = GetIfAddrRetry(overlay);
        overlayCidr = GetCIDRv4Retry(overlay);

    }

    std::string strf;
    std::string strb;
    std::string storageFIf;
    std::string storageBIf;
    std::string storageFAddr;
    std::string storageBAddr;
    std::string storageFCidr;
    std::string storageBCidr;
    if (IfStorageReq(r)) {
        strf = StorPubIf(s_storage.oldValue());
        strb = StorClusterIf(s_storage.oldValue());
        storageFIf = GetParentIf(strf);
        storageBIf = GetParentIf(strb);
        storageFAddr = GetIfAddrRetry(strf);
        storageBAddr = GetIfAddrRetry(strb);
        storageFCidr = GetCIDRv4Retry(strf);
        storageBCidr = GetCIDRv4Retry(strb);
    }

    bool isCtrl = IsControl(r);
    bool isMaster = IsMaster(isCtrl, mgmtAddr, s_ctrlAddrs.oldValue());
    std::string ctrl = GetController(isCtrl, s_hostname.oldValue(), s_controller.oldValue());
    std::string ctrlIp = isCtrl ? mgmtAddr : s_controllerIp.oldValue();
    std::string sharedId = GetSharedId(isCtrl, s_ha.oldValue(), ctrlIp, s_ctrlVip.oldValue());
    std::string external = s_external.oldValue().length() ? s_external.oldValue() : sharedId;

    G_PARSE_OLD(IS_MASTER, isMaster ? "true" : "false");
    G_PARSE_OLD(CTRL, ctrl.c_str());
    G_PARSE_OLD(CTRL_IP, ctrlIp.c_str());
    G_PARSE_OLD(SHARED_ID, sharedId.c_str());
    G_PARSE_OLD(EXTERNAL, external.c_str());

    G_PARSE_OLD(MGMT_IF, mgmtIf.c_str());
    G_PARSE_OLD(PROVIDER_IF, providerIf.c_str());
    G_PARSE_OLD(OVERLAY_IF, overlayIf.c_str());
    G_PARSE_OLD(STORAGE_F_IF, storageFIf.c_str());
    G_PARSE_OLD(STORAGE_B_IF, storageBIf.c_str());

    G_PARSE_OLD(MGMT_ADDR, mgmtAddr.c_str());
    G_PARSE_OLD(OVERLAY_ADDR, overlayAddr.c_str());
    G_PARSE_OLD(STORAGE_F_ADDR, storageFAddr.c_str());
    G_PARSE_OLD(STORAGE_B_ADDR, storageBAddr.c_str());

    G_PARSE_OLD(MGMT_CIDR, mgmtCidr.c_str());
    G_PARSE_OLD(OVERLAY_CIDR, overlayCidr.c_str());
    G_PARSE_OLD(STORAGE_F_CIDR, storageFCidr.c_str());
    G_PARSE_OLD(STORAGE_B_CIDR, storageBCidr.c_str());

#define OLD_KVP_FMT "(old) %10s: %s"

    HexLogInfo(OLD_KVP_FMT, "master", G_OLD(IS_MASTER) ? "true" : "false");
    HexLogInfo(OLD_KVP_FMT, "ctrl", G_OLD(CTRL).c_str());
    HexLogInfo(OLD_KVP_FMT, "ctrl ip", G_OLD(CTRL_IP).c_str());
    HexLogInfo(OLD_KVP_FMT, "shared id", G_OLD(SHARED_ID).c_str());
    HexLogInfo(OLD_KVP_FMT, "external", G_OLD(EXTERNAL).c_str());

#define OLD_FMT "(old) %10s: %s, %s, %s, %s"

    HexLogInfo(OLD_FMT, "mgmt", s_mgmt.oldValue().c_str(), G_OLD(MGMT_IF).c_str(),
                                G_OLD(MGMT_ADDR).c_str(), G_OLD(MGMT_CIDR).c_str());
    HexLogInfo(OLD_FMT, "provider", s_provider.oldValue().c_str(), G_OLD(PROVIDER_IF).c_str(),
                                    "dc", "dc");
    HexLogInfo(OLD_FMT, "overlay", s_overlay.oldValue().c_str(), G_OLD(OVERLAY_IF).c_str(),
                                   G_OLD(OVERLAY_ADDR).c_str(), G_OLD(OVERLAY_CIDR).c_str());
    HexLogInfo(OLD_FMT, "str-f", StorPubIf(s_storage.oldValue()).c_str(), G_OLD(STORAGE_F_IF).c_str(),
                                 G_OLD(STORAGE_F_ADDR).c_str(), G_OLD(STORAGE_F_CIDR).c_str());
    HexLogInfo(OLD_FMT, "str-b", StorClusterIf(s_storage.oldValue()).c_str(), G_OLD(STORAGE_B_IF).c_str(),
                                 G_OLD(STORAGE_B_ADDR).c_str(), G_OLD(STORAGE_B_CIDR).c_str());

    return true;
}


static bool
ParseNew(void)
{
    CubeRole_e r = GetCubeRole(s_cubeRole.newValue());

    std::string mgmt;
    std::string mgmtIf;
    std::string mgmtAddr;
    std::string mgmtCidr;
    if (IfMgmtReq(r)) {
        mgmt = s_mgmt.newValue();
        mgmtIf = GetParentIf(mgmt);
        mgmtAddr = GetIfAddrRetry(mgmt);
        if (mgmtAddr == "0.0.0.0")
            return false;
        mgmtCidr = GetCIDRv4Retry(mgmt);
        if (mgmtCidr == "0.0.0.0/0")
            return false;
    }

    std::string provider;
    std::string providerIf;
    if (IfProviderReq(r)) {
        provider = s_provider.newValue();
        providerIf = provider;
    }

    std::string overlay;
    std::string overlayIf;
    std::string overlayAddr;
    std::string overlayCidr;
    if (IfOverlayReq(r)) {
        overlay = s_overlay.newValue();
        overlayIf = GetParentIf(overlay);
        overlayAddr = GetIfAddrRetry(overlay);
        if (overlayAddr == "0.0.0.0")
            return false;
        overlayCidr = GetCIDRv4Retry(overlay);
        if (overlayCidr == "0.0.0.0/0")
            return false;

    }

    std::string strf;
    std::string strb;
    std::string storageFIf;
    std::string storageBIf;
    std::string storageFAddr;
    std::string storageBAddr;
    std::string storageFCidr;
    std::string storageBCidr;
    if (IfStorageReq(r)) {
        strf = StorPubIf(s_storage.newValue());
        strb = StorClusterIf(s_storage.newValue());
        storageFIf = GetParentIf(strf);
        storageBIf = GetParentIf(strb);
        storageFAddr = GetIfAddrRetry(strf);
        if (storageFAddr == "0.0.0.0")
            return false;
        storageBAddr = GetIfAddrRetry(strb);
        if (storageBAddr == "0.0.0.0")
            return false;
        storageFCidr = GetCIDRv4Retry(strf);
        if (storageFCidr == "0.0.0.0/0")
            return false;
        storageBCidr = GetCIDRv4Retry(strb);
        if (storageBCidr == "0.0.0.0/0")
            return false;
    }

    bool isCtrl = IsControl(s_eCubeRole);
    bool isMaster = IsMaster(isCtrl, mgmtAddr, s_ctrlAddrs.newValue());
    std::string ctrl = GetController(isCtrl, s_hostname.newValue(), s_controller.newValue());
    std::string ctrlIp = isCtrl ? mgmtAddr : s_controllerIp.newValue();
    std::string sharedId = GetSharedId(isCtrl, s_ha.newValue(), ctrlIp, s_ctrlVip.newValue());
    std::string external = s_external.newValue().length() ? s_external.newValue() : sharedId;

    G_PARSE_NEW(IS_MASTER, isMaster ? "true" : "false");
    G_PARSE_NEW(CTRL, ctrl.c_str());
    G_PARSE_NEW(CTRL_IP, ctrlIp.c_str());
    G_PARSE_NEW(SHARED_ID, sharedId.c_str());
    G_PARSE_NEW(EXTERNAL, external.c_str());

    G_PARSE_NEW(MGMT_IF, mgmtIf.c_str());
    G_PARSE_NEW(PROVIDER_IF, providerIf.c_str());
    G_PARSE_NEW(OVERLAY_IF, overlayIf.c_str());
    G_PARSE_NEW(STORAGE_F_IF, storageFIf.c_str());
    G_PARSE_NEW(STORAGE_B_IF, storageBIf.c_str());

    G_PARSE_NEW(MGMT_ADDR, mgmtAddr.c_str());
    G_PARSE_NEW(OVERLAY_ADDR, overlayAddr.c_str());
    G_PARSE_NEW(STORAGE_F_ADDR, storageFAddr.c_str());
    G_PARSE_NEW(STORAGE_B_ADDR, storageBAddr.c_str());

    G_PARSE_NEW(MGMT_CIDR, mgmtCidr.c_str());
    G_PARSE_NEW(OVERLAY_CIDR, overlayCidr.c_str());
    G_PARSE_NEW(STORAGE_F_CIDR, storageFCidr.c_str());
    G_PARSE_NEW(STORAGE_B_CIDR, storageBCidr.c_str());

#define NEW_KVP_FMT "(new) %10s: %s(%s)"

    HexLogInfo(NEW_KVP_FMT, "master", G_NEW(IS_MASTER) ? "true" : "false", G_MOD_STR(IS_MASTER));
    HexLogInfo(NEW_KVP_FMT, "ctrl", G_NEW(CTRL).c_str(), G_MOD_STR(CTRL));
    HexLogInfo(NEW_KVP_FMT, "ctrl ip", G_NEW(CTRL_IP).c_str(), G_MOD_STR(CTRL_IP));
    HexLogInfo(NEW_KVP_FMT, "shared id", G_NEW(SHARED_ID).c_str(), G_MOD_STR(SHARED_ID));
    HexLogInfo(NEW_KVP_FMT, "external", G_NEW(EXTERNAL).c_str(), G_MOD_STR(EXTERNAL));

#define NEW_FMT "(new) %10s: %s(%s), %s(%s), %s(%s), %s(%s)"

    HexLogInfo(NEW_FMT, "mgmt", s_mgmt.c_str(), s_mgmt.modified() ? "v" : "x",
                                G_NEW(MGMT_IF).c_str(), G_MOD_STR(MGMT_IF),
                                G_NEW(MGMT_ADDR).c_str(), G_MOD_STR(MGMT_ADDR),
                                G_NEW(MGMT_CIDR).c_str(), G_MOD_STR(MGMT_CIDR));
    HexLogInfo(NEW_FMT, "provider", s_provider.c_str(), s_provider.modified() ? "v" : "x",
                                    G_NEW(PROVIDER_IF).c_str(), G_MOD_STR(PROVIDER_IF),
                                    "dc", "dc", "dc", "dc");
    HexLogInfo(NEW_FMT, "overlay", s_overlay.c_str(), s_overlay.modified() ? "v" : "x",
                                   G_NEW(OVERLAY_IF).c_str(), G_MOD_STR(OVERLAY_IF),
                                   G_NEW(OVERLAY_ADDR).c_str(), G_MOD_STR(OVERLAY_ADDR),
                                   G_NEW(OVERLAY_CIDR).c_str(), G_MOD_STR(OVERLAY_CIDR));
    HexLogInfo(NEW_FMT, "str-f", StorPubIf(s_storage).c_str(), s_storage.modified() ? "v" : "x",
                                 G_NEW(STORAGE_F_IF).c_str(), G_MOD_STR(STORAGE_F_IF),
                                 G_NEW(STORAGE_F_ADDR).c_str(), G_MOD_STR(STORAGE_F_ADDR),
                                 G_NEW(STORAGE_F_CIDR).c_str(), G_MOD_STR(STORAGE_F_CIDR));
    HexLogInfo(NEW_FMT, "str-b", StorClusterIf(s_storage).c_str(), s_storage.modified() ? "v" : "x",
                                 G_NEW(STORAGE_B_IF).c_str(), G_MOD_STR(STORAGE_B_IF),
                                 G_NEW(STORAGE_B_ADDR).c_str(), G_MOD_STR(STORAGE_B_ADDR),
                                 G_NEW(STORAGE_B_CIDR).c_str(), G_MOD_STR(STORAGE_B_CIDR));

    return true;
}

static bool
ParseNet(const char *name, const char *value, bool isNew)
{
    if (strcmp(name, NET_HOSTNAME) == 0) {
        s_hostname.parse(value, isNew);
    }

    return true;
}

static bool
ParseCube(const char *name, const char *value, bool isNew)
{
    ParseTune(name, value, isNew, 1);
    return true;
}

static void
NotifyNet(bool modified)
{
    s_bNetModified = s_hostname.modified();
}

static void
NotifyCube(bool modified)
{
    s_bCubeModified = IsModifiedTune(1);
    s_eCubeRole = GetCubeRole(s_cubeRole);

    // is not bootstrap, not undef role, and is configured
    if (!IsBootstrap() && !IsUndef(s_eCubeRole) && access(CONFIGURED_FILE, F_OK) == 0 && WithSettings()) {
        // for commands, like regular commands and triggers
        ParseNew();
    }

    // is not the 1st bootstrap and is not a unconfigured cube
    if (IsBootstrap() && access(HEX_DONE, F_OK) == 0 && !IsUndef(s_eCubeRole)) {
        ParseNew();
    }
}

static bool
Prepare(bool modified, int dryLevel)
{
    if (IsBootstrap() || IsUndef(GetCubeRole(s_cubeRole.oldValue())))
        return true;

    ParseOld();

    return true;
}

static bool
Commit(bool modified, int dryLevel)
{
    if (IsUndef(s_eCubeRole))
        return true;

    CubeRole_e r = GetCubeRole(s_cubeRole.newValue());

    if (IfProviderReq(r)) {
        // in case provider interface is disabled in policy
        HexUtilSystemF(0, 0, "/usr/sbin/ip link set %s up", s_provider.c_str());
    }

    return ParseNew();
}

static bool
CommitLast(bool modified, int dryLevel)
{
    if (IsUndef(s_eCubeRole))
        return true;

    if (IsControl(s_eCubeRole) && (G_MOD(SHARED_ID) || G_MOD(EXTERNAL)))
        HexUtilSystemF(0, 0, HEX_SDK " os_endpoint_snapshot_create");

    HexSpawn(0, HEX_SDK, "cube_commit_done", NULL);
    HexSystemF(0, "rm -f %s %s", CUBE_MIGRATE, CONTROL_REJOIN);
    return true;
}

static std::string
GetAllocationPool(const std::string& iplist)
{
    std::string pools = "";

    std::vector<std::string> iprs = hex_string_util::split(iplist, ',');
    for (auto& ipr : iprs) {
        std::vector<std::string> ips = hex_string_util::split(ipr, '-');
        pools += "--allocation-pool ";
        pools += "start=";
        pools += ips[0];
        pools += ",end=";
        pools += ips.size() > 1 ? ips[1] : ips[0];
        pools += " ";
    }

    return pools;
}

static void PasswordInitUsage(void)
{
    fprintf(stderr, "Usage: %s cube_password_init\n", HexLogProgramName());
}

static int PasswordInitMain(int argc, char* argv[])
{
    std::string sharedId = G(SHARED_ID);
    std::string octet3 = hex_string_util::split(sharedId, '.')[2];
    std::string octet4 = hex_string_util::split(sharedId, '.')[3];
    std::string initPass = "Cube@" + octet3 + "." + octet4;

    if (HexSpawn(0, HEX_CFG, "password", "admin", initPass.c_str(), NULL) == 0)
        HexLogInfo("Set administrator password to %s", initPass.c_str());
    else
        HexLogError("Failed to init administrator password");

    return EXIT_SUCCESS;
}

static int
ClusterReadyMain(int argc, char **argv)
{
    std::string args = "";
    if (argc == 4) {
        args += "--subnet-range ";
        args += std::string(argv[1]);
        args += " --gateway ";
        args += std::string(argv[2]);
        args += " ";
        args += GetAllocationPool(std::string(argv[3]));
    }

    if (IsControl(s_eCubeRole)) {
        HexUtilSystemF(0, 0, HEX_SDK " hwdetect_cluster_ready %s", args.c_str());
        HexUtilSystemF(0, 0, HEX_SDK " cube_edge_cfg");
    }

    return EXIT_SUCCESS;
}

CONFIG_MODULE(cube_scan, NULL, NULL, NULL, Prepare, Commit);
CONFIG_OBSERVES(cube_scan, net, ParseNet, NotifyNet);
CONFIG_OBSERVES(cube_scan, cubesys, ParseCube, NotifyCube);

CONFIG_REQUIRES(cube_scan, standalone);

CONFIG_MODULE(cube_last, 0, 0, 0, 0, CommitLast);
CONFIG_REQUIRES(cube_last, monasca_setup);
CONFIG_REQUIRES(cube_last, pacemaker_last);
CONFIG_REQUIRES(cube_last, neutron_last);
CONFIG_LAST(cube_last);

CONFIG_COMMAND_WITH_SETTINGS(cube_password_init, PasswordInitMain, PasswordInitUsage);
CONFIG_TRIGGER_WITH_SETTINGS(cube_last, "cluster_ready", ClusterReadyMain);

