// HEX SDK

#include <cstring>
#include <cstdio>
#include <cstdlib>

#include <string>
#include <set>
#include <map>
#include <list>
#include <regex.h>

#include <hex/log.h>
#include <hex/process.h>
#include <hex/tuning.h>
#include <hex/string_util.h>
#include <hex/strict.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

#include "include/policy_network.h"
#include "include/policy_time.h"
#include "include/policy_cubesys.h"

#include "include/setting_network.h"

#include "include/cli_network.h"
#include "include/cli_password.h"
#include "include/cli_time.h"
#include "include/cli_cubesys.h"
#include "include/cli_cubeha.h"

static const char* LABEL_ROLE = "Role: %s";
static const char* LABEL_CONTROLLER = "Controller: %s(%s)";
static const char* LABEL_EXTERNAL = "External IP/Domain: %s";
static const char* LABEL_MGMT = "Management: %s";
static const char* LABEL_PROVIDER = "Provider: %s";
static const char* LABEL_OVERLAY = "Overlay: %s";
static const char* LABEL_STORAGE = "Storage: %s";
static const char* LABEL_DOMAIN_REGION = "Domain/Region: %s/%s";
static const char* LABEL_SECRET_SEED = "Cube Secret Seed: %s";

static const char* LABEL_HA = "High Availability: %s";
static const char* LABEL_CONTROL_VIP = "Control Virtual IP: %s";
static const char* LABEL_CONTROL_VHN = "Control Virtual Hostname: %s";
static const char* LABEL_CONTROL_GROUP = "Control Group: %s";

static const char* LBL_DNS_AUTO_DISPLAY = "DNS is set to Automatic Configuration";
static const char* LBL_DNS_DISPLAY = "DNS server %d: %s";
static const char* LBL_CHOOSE_DNS = "Select the DNS server to configure:";
static const char* LBL_DNS_IDX = "DNS server %d";

static InterfaceSystemSettings s_sysSettings;

static void
InterfaceParseSys(const char* name, const char* value)
{
    s_sysSettings.build(name, value);
}

CLI_PARSE_SYSTEM_SETTINGS(InterfaceParseSys);

static void
getIfList(const BondingConfig& bcfg, const VlanConfig& vcfg, CliList *iflist)
{
    for (auto iter = s_sysSettings.netIfBegin(); iter != s_sysSettings.netIfEnd(); ++iter) {
        std::string label = "";
        std::string port = (std::string)*iter;

         s_sysSettings.port2Label(*iter, &label);

        // check if its a slave interface
        bool slave = false;
        for (auto& b : bcfg) {
            for (auto& i : b.second) {
                if (i == label) {
                    slave = true;
                    break;
                }
            }
            if (slave)
                break;
        }

        // add non-slave interface to list
        if (label.length() && !slave) {
            iflist->push_back(label);
        }
    }

    // add bonding interface to list
    for (auto& b : bcfg) {
        iflist->push_back(b.first);
    }

    // add vlan interface to list
    for (auto& v : vcfg) {
        iflist->push_back(v.first);
    }
}

static bool
getInterface(int argc, const char** argv,
             const BondingConfig& bcfg, const VlanConfig& vcfg,
             std::string *ifLabel)
{
    CliList iflist;

    getIfList(bcfg, vcfg, &iflist);

    int selected;
    if(CliMatchListHelper(argc, argv, 1, iflist, &selected, ifLabel) != 0) {
        CliPrint("invalid interface");
        return false;
    }

    return true;
}

static void
CubeNetBondingShow(NetworkPolicy& netPolicy)
{
    CliPrintf("\n[Network Bonding Policy]");

    // display network bonding config
    BondingConfig cfg;
    netPolicy.getBondingPolciy(&cfg);

    for (auto& b : cfg) {
        CliPrintf("%s:", b.first.c_str());

        for (auto& i : b.second) {
            CliPrintf("\t%s", i.c_str());
        }
    }
}

static int
CubeBondingMain(HexPolicyManager* policyManager, NetworkPolicy* netPolicy, bool *netBondingChanged)
{
    assert(s_sysSettings.netIfSize() > 0);

    CliNetworkBondingChanger bondingChanger;

    if (bondingChanger.configure(netPolicy, s_sysSettings)) {
        if (!policyManager->save(*netPolicy))
            return CLI_FAILURE;
        else
            *netBondingChanged = true;
    }

    return CLI_SUCCESS;
}

static void
CubeNetVlanShow(NetworkPolicy& netPolicy)
{
    CliPrintf("\n[VLAN Policy]");

    // display network bonding config
    VlanConfig cfg;
    netPolicy.getVlanPolciy(&cfg);

    for (auto& v : cfg) {
        CliPrintf("%s: vlan %d on %s", v.first.c_str(), v.second.vid, v.second.master.c_str());
    }
}

static int
CubeVlanMain(HexPolicyManager* policyManager, NetworkPolicy* netPolicy, bool *netVlanChanged)
{
    assert(s_sysSettings.netIfSize() > 0);

    CliNetworkVlanChanger vlanChanger;

    if (vlanChanger.configure(netPolicy, s_sysSettings)) {
        if (!policyManager->save(*netPolicy))
            return CLI_FAILURE;
        else
            *netVlanChanged = true;
    }

    return CLI_SUCCESS;
}

static void
CubeNetworkShow(NetworkPolicy& netPolicy, bool status = true)
{
    BondingConfig bcfg;
    VlanConfig vcfg;
    netPolicy.getBondingPolciy(&bcfg);
    netPolicy.getVlanPolciy(&vcfg);

    // display network config
    CliList iflist;
    getIfList(bcfg, vcfg, &iflist);

    if (status) {
        CliPrintf("\n[Device Info]");
        HexSpawn(0, HEX_SDK, "-v", "DumpInterface", NULL);

        CliPrintf("\n[Device Status]");
        for (auto iter = s_sysSettings.netIfBegin(); iter != s_sysSettings.netIfEnd(); ++iter) {
            std::string label;
            if (s_sysSettings.port2Label(*iter, &label)) {
                DevicePolicy devPolicy;
                DeviceSystemSettings devSettings;
                if (devSettings.getDevicePolicy(devPolicy, *iter)) {
                    CliPrintf("%s", label.c_str());
                    devPolicy.display();
                }
            }
        }

        // find all device status from bonding configuration
        for (auto& b : bcfg) {
            DevicePolicy devPolicy;
            DeviceSystemSettings devSettings;
            CliPrintf("%s", b.first.c_str());
            if (devSettings.getDevicePolicy(devPolicy, b.first)) {
                devPolicy.display();
            }
        }

        // find all device status from vlan configuration
        for (auto& v : vcfg) {
            DevicePolicy devPolicy;
            DeviceSystemSettings devSettings;
            CliPrintf("%s", v.first.c_str());
            if (devSettings.getDevicePolicy(devPolicy, v.first)) {
                devPolicy.display();
            }
        }
    }

    CliPrintf("\n[Network Policy]");
    for (size_t i = 0 ; i < iflist.size() ; i++) {
        InterfacePolicy ifPolicy;
        if (netPolicy.getInterfacePolciy(ifPolicy, iflist[i])) {
            CliPrintf("%s", iflist[i].c_str());
            ifPolicy.display();
        }
    }
}

static int
CubeNetworkMain(HexPolicyManager* policyManager, NetworkPolicy* netPolicy, bool *netChanged)
{
    assert(s_sysSettings.netIfSize() > 0);

    BondingConfig bcfg;
    VlanConfig vcfg;
    netPolicy->getBondingPolciy(&bcfg);
    netPolicy->getVlanPolciy(&vcfg);

    std::string label;  // The network interface label, eg. IF.1
    if (!getInterface(0, NULL, bcfg, vcfg, &label)) {
        return CLI_FAILURE;
    }

    bool isPrimary = (label == netPolicy->getDefaultInterface());
    CliNetowrkChanger netChanger;

    InterfacePolicy ifPolicy;
    if (netChanger.configure(&ifPolicy, label, isPrimary)) {
        // Being unable to update the policy is a catastrophic failure
        if (!netPolicy->setInterfacePolicy(ifPolicy))
            return CLI_FAILURE;

        if (!policyManager->save(*netPolicy))
            return CLI_FAILURE;
        else
            *netChanged = true;
    }

    return CLI_SUCCESS;
}

static void
CubeSysShow(CubeSysPolicy& sysPolicy)
{
    CliPrintf("\n[Cube System Policy]");

    // display cube sys config
    std::string role = sysPolicy.getRole();
    int roleId = GetCubeRole(role);

    CliPrintf(LABEL_ROLE, role.c_str());
    if(ControlReq(roleId)) {
        CliPrintf(LABEL_CONTROLLER, sysPolicy.getController(), sysPolicy.getControllerIp());
    }

    if(IsControl(roleId) || IsCompute(roleId)) {
        CliPrintf(LABEL_EXTERNAL, sysPolicy.getExternal());
    }

    CliPrintf(LABEL_MGMT, sysPolicy.getMgmt());

    if(IsCompute(roleId)) {
        CliPrintf(LABEL_PROVIDER, sysPolicy.getProvider());
        CliPrintf(LABEL_OVERLAY, sysPolicy.getOverlay());
    }
    if(IsControl(roleId) || IsCompute(roleId) || IsStorage(roleId)) {
        CliPrintf(LABEL_STORAGE, sysPolicy.getStorage());
    }
    CliPrintf(LABEL_DOMAIN_REGION, sysPolicy.getDomain(), sysPolicy.getRegion());
    CliPrintf(LABEL_SECRET_SEED, sysPolicy.getSecretSeed());
}

static int
CubeSysMain(HexPolicyManager* policyManager, CubeSysPolicy* sysPolicy, bool *cubeSysChanged)
{
    CubeSysConfig cfg;

    sysPolicy->getConfig(&cfg);
    CliCubeSysChanger sysChanger;

    if (sysChanger.configure(cfg)) {
        if (!sysPolicy->setConfig(cfg))
            return CLI_FAILURE;

        if (!policyManager->save(*sysPolicy))
            return CLI_FAILURE;
        else
            *cubeSysChanged = true;
    }

    return CLI_SUCCESS;
}

static void
CubeHaShow(CubeSysPolicy& sysPolicy)
{
    CliPrintf("\n[Cube HA Policy]");

    // display cube ha config
    CubeSysConfig sysCfg;
    sysPolicy.getConfig(&sysCfg);
    std::string role = sysPolicy.getRole();
    int roleId = GetCubeRole(role);

    CliPrintf(LABEL_HA, sysPolicy.getHA());
    if (sysCfg.ha) {
        if (IsControl(roleId)) {
            CliPrintf(LABEL_CONTROL_VHN, sysPolicy.getController());
            CliPrintf(LABEL_CONTROL_VIP, sysPolicy.getControlVip());
        }
        CliPrintf(LABEL_CONTROL_GROUP, sysPolicy.getControlGroup().c_str());
    }
}

static int
CubeHaMain(HexPolicyManager* policyManager, CubeSysPolicy* sysPolicy, bool *cubeHaChanged)
{
    CubeSysConfig cfg;

    sysPolicy->getConfig(&cfg);
    CliCubeHaChanger haChanger;

    if (haChanger.configure(&cfg)) {
        if (!sysPolicy->setConfig(cfg))
            return CLI_FAILURE;

        if (!policyManager->save(*sysPolicy))
            return CLI_FAILURE;
        else {
            *cubeHaChanged = true;
        }
    }

    return CLI_SUCCESS;
}

static int
CubeShowMain(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    HexPolicyManager policyManager;
    NetworkPolicy netPolicy;
    CubeSysPolicy sysPolicy;

    if (!policyManager.load(netPolicy) || !policyManager.load(sysPolicy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    CubeNetBondingShow(netPolicy);
    CubeNetVlanShow(netPolicy);
    CubeNetworkShow(netPolicy);
    CubeSysShow(sysPolicy);
    CubeHaShow(sysPolicy);
    CliPrintf("");

    return CLI_SUCCESS;
}

static int
CubeSetMain(int argc, const char** argv)
{
    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    bool netBondingChanged = false;
    bool netVlanChanged = false;
    bool netChanged = false;
    bool cubeSysChanged = false;
    bool cubeHaChanged = false;

    HexPolicyManager policyManager;
    NetworkPolicy netPolicy;
    CubeSysPolicy sysPolicy;

    if (!policyManager.load(netPolicy) || !policyManager.load(sysPolicy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    CliList actions;
    int actIdx;
    std::string action;

    enum {
        UPD_BONDING = 0,
        UPD_VLAN,
        UPD_NETWORK,
        UPD_CUBESYS,
        UPD_CUBEHA,
        APPLY,
        EXIT
    };

    actions.push_back("bonding");
    actions.push_back("vlan");
    actions.push_back("network");
    actions.push_back("cube system");
    actions.push_back("cube ha");
    actions.push_back("apply");
    actions.push_back("exit");

    actIdx = 0;
    while(actIdx != APPLY && actIdx != EXIT) {
        int ret;
        actIdx = CliReadListIndex(actions);
        switch (actIdx) {
            case UPD_BONDING:
                ret = CubeBondingMain(&policyManager, &netPolicy, &netBondingChanged);
                break;
            case UPD_VLAN:
                ret = CubeVlanMain(&policyManager, &netPolicy, &netVlanChanged);
                break;
            case UPD_NETWORK:
                ret = CubeNetworkMain(&policyManager, &netPolicy, &netChanged);
                break;
            case UPD_CUBESYS:
                ret = CubeSysMain(&policyManager, &sysPolicy, &cubeSysChanged);
                break;
            case UPD_CUBEHA:
                ret = CubeHaMain(&policyManager, &sysPolicy, &cubeHaChanged);
                break;
        }

        if (ret != CLI_SUCCESS)
            return ret;
    }

    if (actIdx == EXIT)
        return CLI_SUCCESS;

    bool changed = netBondingChanged | netVlanChanged | netChanged |
                      cubeSysChanged | cubeHaChanged;
    if (!changed) {
        CliPrintf("No policies changed");
        return CLI_SUCCESS;
    }

    if (netBondingChanged)
        CubeNetBondingShow(netPolicy);

    if (netVlanChanged)
        CubeNetVlanShow(netPolicy);

    if (netChanged)
        CubeNetworkShow(netPolicy, false);

    if (cubeSysChanged)
        CubeSysShow(sysPolicy);

    if (cubeHaChanged)
        CubeHaShow(sysPolicy);

    CliPrintf("Apply the changes?");
    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    if (!policyManager.apply(true))
        return CLI_UNEXPECTED_ERROR;

    if (netBondingChanged | netVlanChanged | netChanged)
        HexLogEvent("PLC00001I", "%s,category=policy,policy=network",
                                 CliEventAttrs().c_str());
    if (cubeSysChanged | cubeHaChanged)
        HexLogEvent("PLC00001I", "%s,category=policy,policy=cubesys",
                                 CliEventAttrs().c_str());
    return CLI_SUCCESS;
}

// This mode is not available in STRICT error state
CLI_MODE(CLI_TOP_MODE, "management", "Work with management settings.", !HexStrictIsErrorState() && !FirstTimeSetupRequired());

// This mode is not available in STRICT error state
CLI_MODE("management", "cube", "Work with the cube system settings.", !HexStrictIsErrorState() && !FirstTimeSetupRequired());

CLI_MODE_COMMAND("cube", "show", CubeShowMain, NULL,
        "Display cube configuration, including bonding, network, system, and ha.",
        "show");

CLI_MODE_COMMAND("cube", "set", CubeSetMain, NULL,
        "Set cube configuration, including bonding, network, system, and ha.",
        "set");

static int
HostnameShowMain(int argc, const char** argv)
{
    HexPolicyManager policyManager;
    NetworkPolicy policy;
    if (!policyManager.load(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    CliPrintf("%s", policy.getHostname());

    return CLI_SUCCESS;
}

static int
HostnameSetMain(int argc, const char** argv)
{
    if (argc > 2) {
        return CLI_INVALID_ARGS;
    }

    // Determine the new hostname
    CliHostnameChanger changer;
    std::string hostname;
    bool validated = false;

    // one liner command eg. 'set cube'
    if (argc == 2) {
        hostname = argv[1];
        validated = changer.validate(hostname);
    }
    // interactive mode: eg. 'set'
    else {
        validated = changer.configure(hostname);
    }

    if (!validated) {
        return CLI_FAILURE;
    }

    // Load the current policy from disk
    HexPolicyManager policyManager;
    NetworkPolicy policy;
    if (!policyManager.load(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    // Update the host name
    if (!policy.setHostname(hostname)) {
        return CLI_UNEXPECTED_ERROR;
    }

    // save policy
    if (!policyManager.save(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    // Apply the policy using hex_config apply (translate + commit)
    if (!policyManager.apply()) {
        return CLI_UNEXPECTED_ERROR;
    }

    return CLI_SUCCESS;
}

// This mode is not available in STRICT error state
CLI_MODE("management", "hostname", "Work with the appliance host name.", !HexStrictIsErrorState() && !FirstTimeSetupRequired());

CLI_MODE_COMMAND("hostname", "show", HostnameShowMain, NULL,
        "Show the appliance host name.",
        "show");

CLI_MODE_COMMAND("hostname", "set", HostnameSetMain, NULL,
        "Set the appliance host name.",
        "set [ <hostname> ]");

static int
PasswordMain(int argc, const char** argv)
{

    if (argc > 1) {
        return CLI_INVALID_ARGS;
    }

    PasswordChanger changer;
    if (!changer.configure()) {
        // On error, the password changer will print out an error message
        return CLI_FAILURE;
    }
    return CLI_SUCCESS;

}

CLI_MODE_COMMAND("management", "set_password", PasswordMain, NULL,
        "Set the appliance password.",
        "set_password");

static int
DnsShowMain(int argc, const char** argv)
{
    HexPolicyManager policyManager;
    NetworkPolicy policy;
    if (!policyManager.load(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    if (policy.hasDNSServer()) {
        for (int idx = 0; idx < 3; ++idx) {
            CliPrintf(LBL_DNS_DISPLAY, idx + 1, policy.getDNSServer(idx));
        }
    }
    else {
        CliPrint(LBL_DNS_AUTO_DISPLAY);

        // // Need to display DNS info from admin CLI
        // std::string out = "";
        // int rc = -1;
        // if (HexRunCommand(rc, out, "cat /etc/resolv.conf |grep ^nameserver |awk '{ print $2}'") && rc == 0) {
        //     std::vector<std::string> lines = hex_string_util::split(out, '\n');
        //     for(std::vector<std::string>::size_type i = 0; i != lines.size(); i++) {
        //         hex_string_util::remove(lines[i], '\r');
        //         hex_string_util::remove(lines[i], '\n');
        //         CliPrintf(LBL_DNS_DISPLAY, i + 1, lines[i].c_str());
        //     }
        // }
        // else {
        //     HexLogError("Failed to collect DNS server information");
        // }
    }

    return CLI_SUCCESS;
}

static bool
getDnsIndex(int argc, const char** argv, int &index)
{
    // one liner command. eg. 'set 1 8.8.8.8'
    if (argc > 1) {
        int64_t argVal;
        if (!HexParseInt(argv[1], 1, 3, &argVal)) {
            return false;
        }
        index = argVal - 1;
    }
    // interactive mode 'set'
    else {
        CliPrintf(LBL_CHOOSE_DNS);
        CliList dnsServerList;
        for (int idx = 1; idx <= 3; ++idx) {
            char buffer[256];
            snprintf(buffer, sizeof(buffer), LBL_DNS_IDX, idx);
            dnsServerList.push_back(buffer);
        }

        index = CliReadListIndex(dnsServerList);
        if (index < 0 || index >= 3) {
            return false;
        }
    }

    return true;
}

static bool
getDnsServerIpAddress(int argc, const char** argv, std::string &address)
{
    CliDnsServerChanger changer;
    if (argc == 3) {
        address = argv[2];
        return changer.validate(address);
    }
    else {
        return changer.configure(address);
    }
}

static int
DnsSetMain(int argc, const char** argv)
{
    if (argc > 3) {
        return CLI_INVALID_ARGS;
    }

    int index;
    if (!getDnsIndex(argc, argv, index)) {
        return CLI_FAILURE;
    }

    std::string ipAddress;
    if (!getDnsServerIpAddress(argc, argv, ipAddress)) {
        return CLI_FAILURE;
    }

    // Load the current policy from disk
    HexPolicyManager policyManager;
    NetworkPolicy policy;
    if (!policyManager.load(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    // Update the DNS server
    if (!policy.setDNSServer(index, ipAddress.c_str())) {
        return CLI_UNEXPECTED_ERROR;
    }

    // save policy
    if (!policyManager.save(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    // Apply the policy using hex_config apply (translate + commit)
    if (!policyManager.apply()) {
        return CLI_UNEXPECTED_ERROR;
    }

    return CLI_SUCCESS;
}

// This mode is not available in STRICT error state
CLI_MODE("management", "dns", "Work with the appliance DNS settings.", !HexStrictIsErrorState() && !FirstTimeSetupRequired());

CLI_MODE_COMMAND("dns", "show", DnsShowMain, NULL,
        "Show the appliance DNS settings.",
        "show");

CLI_MODE_COMMAND("dns", "set", DnsSetMain, NULL,
        "Configure the appliance DNS settings.",
        "set [ <DNS-server-index> [ <IP-address> ]]");

static int
FirstRejoinMain(int argc, const char** argv)
{
    if (argc > 2 /* argc[0]: control_rejoin, argc[1]: [set|clear] */)
        return CLI_INVALID_ARGS;

    int index;
    std::string action;

    if (CliMatchCmdHelper(argc, argv, 1, "echo 'set\nclear'", &index, &action, "Set or clear control rejoin flag? ") != CLI_SUCCESS) {
        CliPrintf("Unknown action");
        return CLI_INVALID_ARGS;
    }

    if (index == 0) {
        HexSpawn(0, HEX_SDK, "cube_control_rejoin_set", NULL);
        CliPrintf("Control rejoin markers set");
    }
    else {
        HexSpawn(0, HEX_SDK, "cube_control_rejoin_clear", NULL);
        CliPrintf("Control rejoin markers cleared");
    }

    return CLI_SUCCESS;
}

CLI_MODE(CLI_TOP_MODE, "first", "Work with the first time setup options.", FirstTimeSetupRequired());

CLI_MODE_COMMAND("first", "control_rejoin", FirstRejoinMain, NULL,
        "Set this cube to be control rejoin or undo it. Set it when restoring a failed control node.",
        "control_rejoin [set|clear]");

static int
TimeShowMain(int argc, const char** argv)
{
    if (argc > 1 /* argv[0]: show */)
        return CLI_INVALID_ARGS;

    char buf[255];

    time_t currentTime;
    struct tm currentTm;
    struct tm currentGm;

    // Get the current time
    if (time(&currentTime) == -1) {
        return CLI_UNEXPECTED_ERROR;
    }

    // Convert it into a localtime
    if (localtime_r(&currentTime, &currentTm) == NULL) {
        return CLI_UNEXPECTED_ERROR;
    }

    // Convert it into a GMT/UTC time
    if (gmtime_r(&currentTime, &currentGm) == NULL) {
        return CLI_UNEXPECTED_ERROR;
    }

    // Format the current time into the CLI presented format
    if (strftime(buf, 255, "%m/%d/%Y %H:%M:%S %Z", &currentTm) == 0) {
        return CLI_UNEXPECTED_ERROR;
    }

    CliPrintf("Local Time: %s", buf);

    // Format the current time into the CLI presented format
    if (strftime(buf, 255, "%m/%d/%Y %H:%M:%S %Z", &currentGm) == 0) {
        return CLI_UNEXPECTED_ERROR;
    }

    CliPrintf("  GMT Time: %s", buf);

    return CLI_SUCCESS;
}

static int
TimeTzMain(int argc, const char** argv)
{
    if (argc > 1 /* argv[0]: timezone */)
        return CLI_INVALID_ARGS;

    CliTimeZoneChanger changer;
    std::string timezone;

    if (!changer.configure(timezone)) {
        return CLI_FAILURE;
    }

    // Load the current policy from disk
    HexPolicyManager policyManager;
    TimePolicy policy;

    if (!policyManager.load(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    // Update timezone
    if (!policy.setTimeZone(timezone)) {
        return CLI_UNEXPECTED_ERROR;
    }

    // save policy
    if (!policyManager.save(policy)) {
        return CLI_UNEXPECTED_ERROR;
    }

    // Apply the policy using hex_config apply (translate + commit)
    if (!policyManager.apply()) {
        return CLI_UNEXPECTED_ERROR;
    }

    // Once localtime has been set, call tzset to recalculate the
    // timezone for up-to-date display
    tzset();

    return CLI_SUCCESS;
}

static int
TimeDatetimeMain(int argc, const char** argv)
{
    if (argc != 2 /* argv[0]: datetime, argv[1]: "YYYY-MM-DD hh:mm:ss" */)
        return CLI_INVALID_ARGS;

    const char* DATETIME_FMT = "\"%Y-%m-%d %H:%M:%S\"";

    char buf[255];
    struct tm newTm;

    // Convert the formatted input time into time representation
    if (strptime(argv[1], "%Y-%m-%d %H:%M:%S", &newTm) == 0) {
        CliPrintf("bad datetime format, allow format %s", DATETIME_FMT);
        return CLI_INVALID_ARGS;
    }

    // Format the updated date/time into a format consumable by hex_config
    if (strftime(buf, 255, DATETIME_FMT, &newTm) == 0) {
        CliPrintf("failed to convert time string");
        return CLI_UNEXPECTED_ERROR;
    }

    // Perform the system date/time update
    if (HexSpawn(0, HEX_CFG, "date", buf, ZEROCHAR_PTR) != 0) {
        CliPrintf("Error setting time");
        return CLI_UNEXPECTED_ERROR;
    }

    return CLI_SUCCESS;
}

static int
TimeNtpSyncMain(int argc, const char** argv)
{
    if (argc > 1 /* argv[0]: ntp_sync */)
            return CLI_INVALID_ARGS;

    char buf[255];

    time_t currentTime;
    struct tm currentTm;

    // Get the current time
    if (time(&currentTime) == -1) {
        return CLI_UNEXPECTED_ERROR;
    }

    // Convert it into a localtime
    if (localtime_r(&currentTime, &currentTm) == NULL) {
        return CLI_UNEXPECTED_ERROR;
    }

    // Format the current time into the CLI presented format
    if (strftime(buf, 255, "%m/%d/%Y %H:%M:%S %Z", &currentTm) == 0) {
        return CLI_UNEXPECTED_ERROR;
    }

    CliPrintf("Before NTP Synchronization");
    CliPrintf("  Local Time: %s", buf);

    HexSpawn(0, HEX_SDK, "ntp_makestep", NULL);

    // Get the current time
    if (time(&currentTime) == -1) {
        return CLI_UNEXPECTED_ERROR;
    }

    // Convert it into a localtime
    if (localtime_r(&currentTime, &currentTm) == NULL) {
        return CLI_UNEXPECTED_ERROR;
    }

    // Format the current time into the CLI presented format
    if (strftime(buf, 255, "%m/%d/%Y %H:%M:%S %Z", &currentTm) == 0) {
        return CLI_UNEXPECTED_ERROR;
    }

    CliPrintf("After NTP Synchronization");
    CliPrintf("  Local Time: %s", buf);

    return CLI_SUCCESS;

}

// This mode is not available in STRICT error state
CLI_MODE(CLI_TOP_MODE, "time", "Work with the time settings.", !HexStrictIsErrorState());

CLI_MODE_COMMAND("time", "show", TimeShowMain, NULL,
        "Display current datetime and timezone info.",
        "show");

CLI_MODE_COMMAND("time", "timezone", TimeTzMain, NULL,
        "Set timezone.",
        "timezone");

CLI_MODE_COMMAND("time", "datetime", TimeDatetimeMain, NULL,
        "Set date.",
        "date \"YYYY-MM-DD hh:mm:ss\"");

CLI_MODE_COMMAND("time", "ntp_sync", TimeNtpSyncMain, NULL,
        "Sync datetime with NTP servers.",
        "ntp_sync");

