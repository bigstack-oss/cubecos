// HEX SDK

#include <netinet/in.h>
#include <arpa/inet.h>

#include <hex/log.h>
#include <hex/parse.h>
#include <hex/strict.h>
#include <hex/process.h>
#include <hex/process_util.h>
#include <hex/string_util.h>

#include <hex/cli_module.h>
#include <hex/cli_util.h>

#include <cube/cubesys.h>

#define CUBECTL "/usr/local/bin/cubectl"

static const char* LABEL_NET_IP_LIST = "Enter IP range [IP-IP,IP]: ";
static const char* LABEL_NET_GW_ADDR = "Enter gateway IP address: ";

static int
VRouterStatsMain(int argc, const char** argv)
{
    /*
     * [0]="vrouter_stats"
     */
    if (argc > 1)
        return CLI_INVALID_ARGS;

    HexSpawn(0, HEX_SDK, "network_virtual_router_stats", NULL);

    return CLI_SUCCESS;
}

static bool
ValidateFip(const std::string& allocPools, const uint32_t ipaddr)
{
    if (allocPools.length()) {
        std::vector<std::string> iprs = hex_string_util::split(allocPools, ',');
        for (auto& ipr : iprs) {
            uint32_t hfrom = 0, hto = 0;
            HexParseIPRange(ipr.c_str(), AF_INET, &hfrom, &hto);
            uint32_t from = htonl(hfrom);
            uint32_t to = htonl(hto);

            for (uint32_t ip = from ; ip <= to ; ip++) {
                uint32_t hip = ntohl(ip);
                char ipStr[INET_ADDRSTRLEN];
                inet_ntop(AF_INET, &hip, ipStr, INET_ADDRSTRLEN);
                if (ipaddr == hip) {
                    return true;
                }
            }
        }
    }

    return false;
}

static int
FipRangeCreateMain(int argc, const char** argv)
{
    if (argc > 5 /* [0]="range_create" [1]="domain" [2]="tenant" [3]="network" [4]="ip_list" */)
        return CLI_INVALID_ARGS;

    int index;
    std::string domain, tenant, network, ipList;
    std::string cmd;

    cmd = HEX_SDK " os_list_domain_basic";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &tenant, "Select tenant: ") != CLI_SUCCESS) {
        CliPrintf("Invalid tenant");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_list_provider_network_basic";
    if (CliMatchCmdHelper(argc, argv, 3, cmd, &index, &network, "Select external network: ") != CLI_SUCCESS) {
        CliPrintf("Invalid external network");
        return CLI_INVALID_ARGS;
    }

    std::string allocPools = HexUtilPOpen(HEX_SDK " os_get_network_alloc_pools_by_tenant_and_name %s %s", tenant.c_str(), network.c_str());
    CliPrintf("network IP allocation pools: %s", allocPools.c_str());

    if (!CliReadInputStr(argc, argv, 4, LABEL_NET_IP_LIST, &ipList) ||
        !HexParseIPList(ipList.c_str(), AF_INET)) {
        CliPrintf("Invalid IP list %s\n", ipList.c_str());
        return CLI_INVALID_ARGS;
    }

    if (ipList.length()) {
        std::vector<std::string> iprs = hex_string_util::split(ipList, ',');
        for (auto& ipr : iprs) {
            uint32_t hfrom = 0, hto = 0;
            HexParseIPRange(ipr.c_str(), AF_INET, &hfrom, &hto);
            uint32_t from = htonl(hfrom);
            uint32_t to = htonl(hto);

            for (uint32_t ip = from ; ip <= to ; ip++) {
                uint32_t hip = ntohl(ip);
                char ipStr[INET_ADDRSTRLEN];
                inet_ntop(AF_INET, &hip, ipStr, INET_ADDRSTRLEN);
                if (ValidateFip(allocPools, hip)) {
                    CliPrintf("creating floating IP %s", ipStr);
                    HexUtilSystemF(0, 0, ". /etc/admin-openrc.sh && "
                                         "/usr/bin/openstack floating ip create "
                                         "--floating-ip-address %s --project %s %s",
                                         ipStr, tenant.c_str(), network.c_str());
                }
                else {
                    CliPrintf("skipping IP %s which does not belong to allocation pools", ipStr);
                }
            }
        }
    }

    return CLI_SUCCESS;
}

static int
RouterSetGatewayMain(int argc, const char** argv)
{
    std::string msg;

    if (argc > 5 /* [0]="set_external_gateway" [1]="domain" [2]="tenant" [3]="router" [4]="gateway" */)
        return CLI_INVALID_ARGS;

    int index;
    struct in_addr v4addr;
    std::string domain, tenant, router, gateway;
    std::string cmd;

    cmd = HEX_SDK " os_list_domain_basic";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &tenant, "Select tenant: ") != CLI_SUCCESS) {
        CliPrintf("Invalid tenant");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_list_router_by_project_basic " + tenant;;
    if (CliMatchCmdHelper(argc, argv, 3, cmd, &index, &router, "Select router: ") != CLI_SUCCESS) {
        CliPrintf("Invalid router");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 4, LABEL_NET_GW_ADDR, &gateway) ||
        !HexParseIP(gateway.c_str(), AF_INET, &v4addr)) {
        CliPrintf("Invalid gateway IP address %s\n", gateway.c_str());
        return CLI_INVALID_ARGS;
    }

    if (gateway.length()) {
        CliPrintf("Set gateway %s for %s of project %s",
                  gateway.c_str(), router.c_str(), tenant.c_str());
        if (HexUtilSystemF(0, 0, HEX_SDK " os_set_router_ext_gateway %s %s %s",
                                 tenant.c_str(), router.c_str(), gateway.c_str()) == 0)
            CliPrintf("Success");
        else
            CliPrintf("Failed");
    }

    return CLI_SUCCESS;
}

static int
QuotaSetMain(int argc, const char** argv)
{
    if (argc > 5 /* [0]="quota_set" [1]="domain" [2]="tenant" [3]="type" [4]="quota" */)
        return CLI_INVALID_ARGS;

    int index;
    std::string domain, tenant, type, quota;
    std::string cmd;

    cmd = HEX_SDK " os_list_domain_basic";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &tenant, "Select tenant: ") != CLI_SUCCESS) {
        CliPrintf("Invalid tenant");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_neutron_quota_list";
    if (CliMatchCmdHelper(argc, argv, 3, cmd, &index, &type, "Select type: ") != CLI_SUCCESS) {
        CliPrintf("Invalid quota type");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadInputStr(argc, argv, 4, "Input quota value: ", &quota) ||
        quota.length() <= 0) {
        CliPrint("quota value is required");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_neutron_quota_update", tenant.c_str(), type.c_str(), quota.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
QuotaShowMain(int argc, const char** argv)
{
    if (argc > 3 /* [0]="quota_show" [1]="domain" [2]="tenant" */)
        return CLI_INVALID_ARGS;

    int index;
    std::string domain, tenant;
    std::string cmd;

    cmd = HEX_SDK " os_list_domain_basic";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &tenant, "Select tenant: ") != CLI_SUCCESS) {
        CliPrintf("Invalid tenant");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_neutron_quota_show", tenant.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
NetSetMain(int argc, const char** argv)
{
    if (argc > 6 /* [0]="network_set" [1]="domain" [2]="tenant" [3]="network" [4]="type" [5]="value" */)
        return CLI_INVALID_ARGS;

    int index;
    std::string domain, tenant, network, type, value;
    std::string cmd;

    cmd = HEX_SDK " os_list_domain_basic";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &tenant, "Select tenant: ") != CLI_SUCCESS) {
        CliPrintf("Invalid tenant");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_list_network_by_project_basic " + tenant;
    if (CliMatchCmdHelper(argc, argv, 3, cmd, &index, &network, "Select network: ") != CLI_SUCCESS) {
        CliPrintf("Invalid network");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_neutron_network_opt_list";
    if (CliMatchCmdHelper(argc, argv, 4, cmd, &index, &type, "Select type: ") != CLI_SUCCESS) {
        CliPrintf("Invalid type");
        return CLI_INVALID_ARGS;
    }

    if (type.rfind("no-", 0) == 0)
        value = "";
    else {
        if (!CliReadInputStr(argc, argv, 5, "Input value: ", &value) ||
            value.length() <= 0) {
            CliPrint("value is required");
            return CLI_INVALID_ARGS;
        }
    }

    HexSpawn(0, HEX_SDK, "os_neutron_network_update",
                         tenant.c_str(), network.c_str(),
                         type.c_str(), value.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
NetShowMain(int argc, const char** argv)
{
    if (argc > 4 /* [0]="network_show" [1]="domain" [2]="tenant" [3]="network" */)
        return CLI_INVALID_ARGS;

    int index;
    std::string domain, tenant, network;
    std::string cmd;

    cmd = HEX_SDK " os_list_domain_basic";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &tenant, "Select tenant: ") != CLI_SUCCESS) {
        CliPrintf("Invalid tenant");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_list_network_by_project_basic " + tenant;
    if (CliMatchCmdHelper(argc, argv, 3, cmd, &index, &network, "Select network: ") != CLI_SUCCESS) {
        CliPrintf("Invalid network");
        return CLI_INVALID_ARGS;
    }

    HexSpawn(0, HEX_SDK, "os_neutron_network_show", tenant.c_str(), network.c_str(), NULL);

    return CLI_SUCCESS;
}

static int
FlowSwitchMain(int argc, const char** argv)
{
    if (argc > 2 /* [0]="set_flowdata" [1]="[on|off]" */)
        return CLI_INVALID_ARGS;

    int index;
    std::string value, msg;

    if (HexSpawn(0, HEX_SDK, "ovn_sflow_status", NULL) == 0)
        msg = "Status: on";
    else
        msg = "Status: off";

    msg += "\nSet flow data:";

    if (CliMatchCmdHelper(argc, argv, 1, "echo 'on\noff'", &index, &value, msg.c_str()) != CLI_SUCCESS) {
        CliPrintf("Unknown action");
        return CLI_INVALID_ARGS;
    }

    switch(index) {
        case 0:
            HexSpawn(0, CUBECTL, "node", "exec", "-r", "compute", "-p", HEX_CFG, "enable_sflow", ZEROCHAR_PTR);
            break;
        case 1:
            HexSpawn(0, CUBECTL, "node", "exec", "-r", "compute", "-p", HEX_CFG, "disable_sflow", ZEROCHAR_PTR);
            break;
    }

    return CLI_SUCCESS;
}

static int
LoadBalancerFixMain(int argc, const char** argv)
{
    if (argc > 4 /* [0]="fix" [1]="domain" [2]="tenant" [3]="lb_id" */)
        return CLI_INVALID_ARGS;

    int index;
    std::string domain, tenant, lb_id;
    std::string cmd;

    cmd = HEX_SDK " os_list_domain_basic";
    if (CliMatchCmdHelper(argc, argv, 1, cmd, &index, &domain, "Select domain: ") != CLI_SUCCESS) {
        CliPrintf("Invalid domain");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_list_project_by_domain_basic " + domain;
    if (CliMatchCmdHelper(argc, argv, 2, cmd, &index, &tenant, "Select tenant: ") != CLI_SUCCESS) {
        CliPrintf("Invalid tenant");
        return CLI_INVALID_ARGS;
    }

    cmd = HEX_SDK " os_list_loadbalancer_by_project_basic " + tenant;
    if (CliMatchCmdHelper(argc, argv, 3, cmd, &index, &lb_id, "Select a load balancer to fix: ") != CLI_SUCCESS) {
        CliPrintf("Invalid load balancer or not found");
        return CLI_INVALID_ARGS;
    }

    if (!CliReadConfirmation())
        return CLI_SUCCESS;

    HexSystemF(0, HEX_SDK " os_octavia_lb_fix %s", lb_id.c_str());

    return CLI_SUCCESS;
}

// This mode is not available in STRICT error state
CLI_MODE(CLI_TOP_MODE, "iaas",
    "Work with IaaS settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("iaas", "vrouter_stats", VRouterStatsMain, NULL,
    "Display virtual router stats.",
    "vrouter_stats");

// This mode is not available in STRICT error state
CLI_MODE("iaas", "fip",
    "Work with the IaaS floating IP settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("fip", "range_create", FipRangeCreateMain, NULL,
    "Allocate floating IP addresses by giving a IP list.",
    "range_create [<domain>] [<tenant>] [<network>] [<ip list>]");

CLI_MODE("iaas", "router",
    "Work with the IaaS router settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("router", "set_external_gateway", RouterSetGatewayMain, NULL,
    "Specify IP addresses for router external gateway.",
    "set_external_gateway [<domain>] [<tenant>] [<router>] [<gateway>]");

CLI_MODE("iaas", "network",
    "Work with the network settings.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("network", "quota_set", QuotaSetMain, NULL,
    "Set network quota for a tenant.",
    "quota_set [<domain>] [<tenant>] [<type>] [<quota>]");

CLI_MODE_COMMAND("network", "quota_show", QuotaShowMain, NULL,
    "Show network quota for a tenant.",
    "quota_show [<domain>] [<tenant>]");

CLI_MODE_COMMAND("network", "network_set", NetSetMain, NULL,
    "Set attribute of a tenant network.",
    "network_set [<domain>] [<tenant>] [<network>] [<type>] [<value>]");

CLI_MODE_COMMAND("network", "network_show", NetShowMain, NULL,
    "Show a tenant network.",
    "network_show [<domain>] [<tenant>] [<network>]");

CLI_MODE("iaas", "flowdata",
    "Work with the network flow data.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("flowdata", "set_flowdata", FlowSwitchMain, NULL,
    "Set on to enable collecting flow data on this node and set off to disable.",
    "set_flowdata [on|off]");

CLI_MODE("iaas", "lb",
    "Work with the IaaS load balancers.",
    !HexStrictIsErrorState() && !FirstTimeSetupRequired() && CubeSysCommitAll());

CLI_MODE_COMMAND("lb", "fix", LoadBalancerFixMain, NULL,
    "Fix load balancer.",
    "fix [<domain>] [<tenant>] [<lb_id>]");
