// HEX SDK

#include <hex/config_module.h>

#include <include/role_cubesys.h>

CONFIG_TUNING(NET_HOSTNAME, "net.hostname", TUNING_UNPUB, "Set appliance hostname.");

// private tunings
CONFIG_TUNING_STR(CUBESYS_ROLE, "cubesys.role", TUNING_UNPUB, "Set the role of cube appliance.", "undef", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_DOMAIN, "cubesys.domain", TUNING_UNPUB, "Set the domain of cube appliance.", DOMAIN_DEF, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_REGION, "cubesys.region", TUNING_UNPUB, "Set the region of cube appliance.", REGION_DEF, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_CONTROLLER, "cubesys.controller", TUNING_UNPUB, "Set controller.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_CONTROLLER_IP, "cubesys.controller.ip", TUNING_UNPUB, "Set controller IP address.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_MGMT, "cubesys.management", TUNING_UNPUB, "Set management interface.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_PROVIDER, "cubesys.provider", TUNING_UNPUB, "Set provider interface.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_OVERLAY, "cubesys.overlay", TUNING_UNPUB, "Set overlay network interface.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_STORAGE, "cubesys.storage", TUNING_UNPUB, "Set storage network interface.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_COMPUTE_PREFIX, "cubesys.compute.prefix", TUNING_UNPUB, "Set compute node host prefix.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_COMPUTE_START, "cubesys.compute.start", TUNING_UNPUB, "Set compute node start IPv4 address.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_INT(CUBESYS_COMPUTE_NUMBER, "cubesys.compute.number", TUNING_UNPUB, "Set max compute node number.", 0, 1, 255);
CONFIG_TUNING_STR(CUBESYS_SEED, "cubesys.seed", TUNING_UNPUB, "Set CubeCOS cluster secret seed.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_MGMT_CIDR, "cubesys.mgmt.cidr", TUNING_UNPUB, "Set CubeCOS cluster management CIDR.", MGMT_CIDR_DEF, ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_CONTROL_VIP, "cubesys.control.vip", TUNING_UNPUB, "Set cluster virtual ip.", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_CONTROL_HOSTS, "cubesys.control.hosts", TUNING_UNPUB, "Set control group hostname [hostname,hostname,...].", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_CONTROL_ADDRS, "cubesys.control.addrs", TUNING_UNPUB, "Set control group address [ip,ip,...].", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_STORAGE_HOSTS, "cubesys.storage.hosts", TUNING_UNPUB, "Set storage group hostname [hostname,hostname,...].", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_STR(CUBESYS_STORAGE_ADDRS, "cubesys.storage.addrs", TUNING_UNPUB, "Set storage group address [ip,ip,...].", "", ValidateRegex, DFT_REGEX_STR);
CONFIG_TUNING_BOOL(CUBESYS_HA, "cubesys.ha", TUNING_UNPUB, "Set true for indicate a HA setup.", false);
CONFIG_TUNING_BOOL(CUBESYS_SALTKEY, "cubesys.saltkey", TUNING_UNPUB, "Set true for enabling key scrambling.", false);

bool
GetIPAddr(const char* ifname, char* ipaddr, int len, int af)
{
    ipaddr[0] = '9';
    ipaddr[1] = '.';
    ipaddr[2] = '4';
    ipaddr[3] = '.';
    ipaddr[4] = '8';
    ipaddr[5] = '.';
    ipaddr[6] = '7';
    return true;
}

CONFIG_MODULE(net, NULL, NULL, NULL, NULL, NULL);
CONFIG_MODULE(cubesys, NULL, NULL, NULL, NULL, NULL);
CONFIG_MODULE(haproxy, NULL, NULL, NULL, NULL, NULL);
CONFIG_MODULE(standalone, NULL, NULL, NULL, NULL, NULL);
