// HEX SDK

#include <unistd.h>

#include <netinet/ip.h>
#include <arpa/inet.h>

#include <list>

#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/log.h>
#include <hex/strict.h>
#include <hex/parse.h>
#include <hex/string_util.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

#define REMOTE_RUN_FMT "sshpass -p admin ssh -o StrictHostKeyChecking=no -t root@%s "
#define STDERR_NULL " 2>/dev/null"

static const char* LABEL_IFNAME = "Select an interface: ";
static const char* LABEL_IFNAME_INPUT = "Specify interface name: ";
static const char* LABEL_BOND = "Specify bond name: ";
static const char* LABEL_SLAVES = "Specify bond slaves (e.g. ethX,ethY): ";
static const char* LABEL_CIDR = "Specify CIDR: ";
static const char* LABEL_VLANID = "Input VLAN ID (1-4095): ";
static const char* LABEL_IPRANGES = "Input IP ranges (IP,IP-IP,...): ";
static const char* LABEL_IPRANGES_OPT = "Press enter for local or input IP ranges (IP,IP-IP,...): ";
static const char* LABEL_TYPE = "Select interface type: ";

static void
GetIpList(const std::string& ipranges, CliList* iplist)
{
    iplist->clear();
    std::vector<std::string> iprs = hex_string_util::split(ipranges, ',');

    for (auto& ipr : iprs) {
        uint32_t hfrom = 0, hto = 0;
        if (HexParseIPRange(ipr.c_str(), AF_INET, &hfrom, &hto)) {
            uint32_t from = htonl(hfrom);
            uint32_t to = htonl(hto);
            for (uint32_t ip = from ; ip <= to ; ip++) {
                struct in_addr ip_addr;
                ip_addr.s_addr = ntohl(ip);
                iplist->push_back(std::string(inet_ntoa(ip_addr)));
            }
        }
    }
}

static int
SetIfMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="set_interface", [1]=<name>, [2]=<cidr> */)
        return CLI_INVALID_ARGS;

    int index = 0;
    std::string name, cidr, cmd;

    HexSpawn(0, HEX_SDK, "-v", "DumpInterface", "0", NULL);

    cmd = "/usr/sbin/ip link | awk -F'[: ]' '/eth.*mtu/{print $3}' | sort -V";
    if(CliMatchCmdHelper(argc, argv, 1, cmd, &index, &name, LABEL_IFNAME) != CLI_SUCCESS) {
        CliPrintf("interface name is missing or not found");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 2, LABEL_CIDR, &cidr) || cidr.length() == 0) {
        CliPrintf("invalid cidr %s", cidr.c_str());
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "preset_interface_set", name.c_str(), cidr.c_str(), NULL);


    return CLI_SUCCESS;
}

static int
SetBondMain(int argc, const char** argv)
{
    if (argc > 4 /* [0]="set_bond_interface", [1]=<name>, [2]=<slaves>, [3]=<cidr> */)
        return CLI_INVALID_ARGS;

    std::string name, slaves, cidr;

    HexSpawn(0, HEX_SDK, "-v", "DumpInterface", "0", NULL);

    if (!CliReadInputStr(argc, argv, 1, LABEL_BOND, &name) || name.length() == 0) {
        CliPrintf("bond name is missing or not found");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 2, LABEL_SLAVES, &slaves) || slaves.length() == 0) {
        CliPrintf("slaves are missing or not found");
        return CLI_INVALID_ARGS;
    }

    CliReadInputStr(argc, argv, 3, LABEL_CIDR, &cidr);

    HexSpawn(0, HEX_SDK, "preset_bond_set", name.c_str(), slaves.c_str(), cidr.c_str(), NULL);


    return CLI_SUCCESS;
}

static int
SetVlanMain(int argc, const char** argv)
{
    if (argc > 4 /* [0]="set_vlan_interface", [1]=<name>, [2]=<vlan id>, [3]=<cidr> */)
        return CLI_INVALID_ARGS;

    std::string name, vid, cidr;

    HexSpawn(0, HEX_SDK, "-v", "DumpInterface", "0", NULL);

    if (!CliReadInputStr(argc, argv, 1, LABEL_IFNAME_INPUT, &name) || name.length() == 0) {
        CliPrintf("interface name is missing or not found");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 2, LABEL_VLANID, &vid) || !HexValidateUInt(vid.c_str(), 1, 4095)) {
        CliPrintf("VLAN ID is missing or invalid");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 3, LABEL_CIDR, &cidr) || cidr.length() == 0) {
        CliPrintf("CIDR is missing or not found");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "preset_vlan_set", name.c_str(), vid.c_str(), cidr.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
ClearIfMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="clear_interface", [1]=<eth|bond|vlan>, [2]=<name> */)
        return CLI_INVALID_ARGS;

    int index = 0;
    std::string type, name;

    HexSpawn(0, HEX_SDK, "-v", "DumpInterface", "0", NULL);

    if(CliMatchCmdHelper(argc, argv, 1, "echo 'eth\nbond\nvlan\nall'", &index, &type, LABEL_TYPE) != CLI_SUCCESS) {
        CliPrintf("interface name is missing or not found");
        return CLI_INVALID_ARGS;
    }

    if (type == "all") {
        HexSpawn(0, HEX_SDK, "preset_interterface_clearall", NULL);
    } else {
        if (!CliReadInputStr(argc, argv, 2, LABEL_IFNAME_INPUT, &name) || name.length() == 0) {
            CliPrintf("interface name is missing or not found");
            return CLI_INVALID_ARGS;
        }
        HexSpawn(0, HEX_SDK, "preset_interterface_clear", type.c_str(), name.c_str(), NULL);
    }

    return CLI_SUCCESS;
}

static int
ShowIfMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="show_interface", [1]=<all|[ifname]>, [2]=<ip-ranges> */)
        return CLI_INVALID_ARGS;

    std::string name, iprs;
    CliList iplist;

    if (!CliReadInputStr(argc, argv, 1, "Press enter to show all or specify an interface: ", &name) || name.length() == 0)
        name = "all";

    if (!CliReadInputStr(argc, argv, 2, LABEL_IPRANGES_OPT, &iprs) || iprs.length() == 0)
        iprs = "local";

    if (iprs.length() && iprs != "local") {
        GetIpList(iprs, &iplist);
        for (auto& ip : iplist) {
            CliPrintf("\nhost: %s", ip.c_str());
            CliPrint("--------------");
            HexSystemF(0, REMOTE_RUN_FMT HEX_SDK " -v preset_interface_show %s" STDERR_NULL, ip.c_str(), name.c_str());
        }
    }
    else {
        HexSpawn(0, HEX_SDK, "-v", "preset_interface_show", name.c_str(), NULL);
    }

    return CLI_SUCCESS;
}

static int
SetDatetimeMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="set_datetime", [1]=<datetime>, [2]=<ip-ranges> */)
        return CLI_INVALID_ARGS;

    std::string datetime, iprs;
    CliList iplist;

    if (!CliReadInputStr(argc, argv, 1, "Input datetime (YYYY-MM-DD hh:mm:ss): ", &datetime) || datetime.length() == 0) {
        CliPrintf("datetime is missing or not found");
        return CLI_INVALID_ARGS;
    }

    std::vector<std::string> dt = hex_string_util::split(datetime, ' ');

    if (!CliReadInputStr(argc, argv, 2, LABEL_IPRANGES_OPT, &iprs) || iprs.length() == 0)
        iprs = "local";

    if (iprs.length() && iprs != "local") {
        GetIpList(iprs, &iplist);
        for (auto& ip : iplist) {
            CliPrintf("\nhost: %s %s %s", ip.c_str(), dt[0].c_str(), dt[1].c_str());
            CliPrint("--------------");
            HexSystemF(0, REMOTE_RUN_FMT HEX_CFG " datetime %s %s" STDERR_NULL, ip.c_str(), dt[0].c_str(), dt[1].c_str());
        }
    }
    else {
        HexSystemF(0, HEX_CFG " date '\"%s\"'", datetime.c_str());
    }

    return CLI_SUCCESS;
}

static int
ShowDatetimeMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="show_datetime", [1]=<ip-ranges> */)
        return CLI_INVALID_ARGS;

    std::string iprs;
    CliList iplist;

    if (!CliReadInputStr(argc, argv, 1, LABEL_IPRANGES_OPT, &iprs) || iprs.length() == 0)
        iprs = "local";

    if (iprs.length() && iprs != "local") {
        GetIpList(iprs, &iplist);
        for (auto& ip : iplist) {
            CliPrintf("\nhost: %s", ip.c_str());
            CliPrint("--------------");
            HexSystemF(0, REMOTE_RUN_FMT HEX_SDK " preset_datetime_show" STDERR_NULL, ip.c_str());
        }
    }
    else {
        HexSpawn(0, HEX_SDK, "preset_datetime_show", NULL);
    }

    return CLI_SUCCESS;
}

static int
PingTargetsMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="ping", [1]=<ip-ranges> */)
        return CLI_INVALID_ARGS;

    std::string iprs;
    CliList iplist;

    if (!CliReadInputStr(argc, argv, 1, LABEL_IPRANGES, &iprs) || iprs.length() == 0) {
        CliPrintf("ip range is missing or invalid");
        return CLI_INVALID_ARGS;
    }

    GetIpList(iprs, &iplist);
    for (auto& ip : iplist) {
        HexSpawn(0, HEX_SDK, "preset_ping", ip.c_str(), NULL);
    }

    return CLI_SUCCESS;
}

CLI_MODE(CLI_TOP_MODE, "preset", "Preset cluster before first time setup.",
    !HexStrictIsErrorState() && FirstTimeSetupRequired());

CLI_MODE_COMMAND("preset", "set_interface", SetIfMain, NULL,
    "set network interface immediately.",
    "set_interface <name> <cidr>");

CLI_MODE_COMMAND("preset", "set_bond_interface", SetBondMain, NULL,
    "set bonding network interface immediately.",
    "set_bond_interface <name> <slaves> <cidr>");

CLI_MODE_COMMAND("preset", "set_vlan_interface", SetVlanMain, NULL,
    "set vlan network interface immediately.",
    "set_vlan_interface <name> <vlan id> <cidr>");

CLI_MODE_COMMAND("preset", "clear_interface", ClearIfMain, NULL,
    "clear network interface settings immediately.",
    "clear_interface <eth|bond|vlan|all> <name>");

CLI_MODE_COMMAND("preset", "show_interface", ShowIfMain, NULL,
    "dump network interfaces status for nodes.",
    "show_interface [all|<ifname>] [local|<IP,IP-IP,...>]");

CLI_MODE_COMMAND("preset", "set_datetime", SetDatetimeMain, NULL,
    "set date and time for nodes.",
    "set_datetime \"<YYYY-MM-DD hh:mm:ss>\" [local|<IP,IP-IP,...>]");

CLI_MODE_COMMAND("preset", "show_datetime", ShowDatetimeMain, NULL,
    "show date and time for nodes.",
    "show_datetime [local|<IP,IP-IP,...>]");

CLI_MODE_COMMAND("preset", "ping", PingTargetsMain, NULL,
    "check network connectivity.",
    "ping <IP,IP-IP,...>");

