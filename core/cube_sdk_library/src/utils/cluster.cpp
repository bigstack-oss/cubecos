// CUBE SDK

#include <string>
#include <algorithm>
#include <thread>

#include <unistd.h>
#include <hex/log.h>
#include <hex/string_util.h>
#include <hex/crypto.h>

#include <cube/network.h>

#define ConvergedRatio  16

int
GetControlWorkers(bool isConverged, bool isEdge)
{
    if (isEdge) {
        return 1;
    }

    int workers = 0;
    unsigned int totalCpus = std::thread::hardware_concurrency();
    // reserve more cpu and ram for converged nodes
    int multiple = isConverged ? 1 : 2;

#define MAX(x, y) (x > y ? x : y)
#define MIN(x, y) (x < y ? x : y)

    // worker must be greater than zero
    workers = MAX(totalCpus / ConvergedRatio * multiple, 1);
    // max 3 workers are best for responese time
    workers = MIN(workers, 3);

#undef MAX
#undef MIN

    return workers;
}

std::string
GetSaltBytesInBase64(bool saltkey, const int len, const std::string& key, const std::string& salt)
{
    std::string pass = key;

    if (!saltkey)
        return pass;

    HexCryptoGetBytesInBase64(len, key, salt, &pass);

    return pass;
}

std::string
GetSaltKey(bool saltkey, const std::string& key, const std::string& salt)
{
    std::string pass = key;

    if (!saltkey)
        return pass;

    HexCryptoGetPassphrase(16, key, salt, &pass);

    // replace all special characters appear in b64 encoding table
    std::replace(pass.begin(), pass.end(), '+', 'p');   // replace all + to p
    std::replace(pass.begin(), pass.end(), '/', 'S');   // replace all / to S
    std::replace(pass.begin(), pass.end(), '=', 'e');   // replace all = to e

    return pass;
}

std::string
GetControlId(bool isCtrl, std::string hostname, std::string controller)
{
    return isCtrl ? hostname : controller;
}

std::string
GetSharedId(bool isCtrl, bool ha, const std::string& ctrl, const std::string& ctrlVid)
{
    return (isCtrl && ha) ? ctrlVid : ctrl;
}

std::string
GetIfAddr(std::string ifname)
{
    char ipaddr[64] = {0};
    if (!GetIPAddr(ifname.c_str(), ipaddr, sizeof(ipaddr), AF_INET)) {
        HexLogError("failed to read %s ipv4 address, return 0.0.0.0", ifname.c_str());
        return "0.0.0.0";
    }

    return ipaddr;
}

std::string
GetControllerIp(bool isCtrl, std::string controllerIp, std::string mgmtIf)
{
    if (!isCtrl)
        return controllerIp;

    return GetIfAddr(mgmtIf);
}

size_t
GetClusterSize(bool ha, const std::string& clusterGroup)
{
    if (!ha)
        return 1;

    return hex_string_util::split(clusterGroup.c_str(), ',').size();
}

bool
IsMaster(bool isCtrl, const std::string& hostname, const std::string& clusterHosts)
{
    if (!isCtrl)
        return false;

    auto hosts = hex_string_util::split(clusterHosts, ',');

    if (hosts.size() == 0)
        return true;

    return (hosts[0].compare(hostname) == 0);
}

std::string
GetMaster(const std::string& clusterGroup)
{
    auto groups = hex_string_util::split(clusterGroup, ',');

    if (groups.size() == 0)
        return "";

    return groups[0];
}

std::string
GetMaster(const bool ha, const std::string& controller, const std::string& controlGroup)
{
    if (!ha)
        return controller;
    else {
        std::string master = GetMaster(controlGroup);
        return master == "" ? controller : master;
    }
}

std::vector<std::string>
GetControllerPeers(const std::string& self, const std::string& controlGroup)
{
    auto hosts = hex_string_util::split(controlGroup, ',');
    std::vector<std::string> peers(0);

    for (auto host : hosts) {
        if (self != host)
            peers.push_back(host);
    }

    return peers;
}

std::string
MemcachedServers(const bool ha, const std::string& controller, const std::string& clusterGroup)
{
    if (!ha)
        return controller + ":11211";
    else {
        auto group = hex_string_util::split(clusterGroup, ',');
        std::string servers = "";
        for (size_t i = 0 ; i < group.size() ; i++) {
            servers += group[i] + ":11211";
            if (i + 1 < group.size())
                servers += ",";
        }

        return servers;
    }
}

std::string
RabbitMqServers(const bool ha, const std::string& controller,
                const std::string& pass, const std::string& clusterGroup)
{
    if (!ha)
        return "rabbit://openstack:" + pass + "@" + controller + ":5672";
    else {
        auto group = hex_string_util::split(clusterGroup, ',');
        std::string servers = "rabbit://";
        for (size_t i = 0 ; i < group.size() ; i++) {
            servers += "openstack:" + pass + "@" + group[i] + ":5672";
            if (i + 1 < group.size())
                servers += ",";
        }

        return servers;
    }
}

std::string
KafkaServers(const bool ha, const std::string& controller, const std::string& clusterGroup, bool quote)
{
    std::string q = quote ? "\"" : "";

    if (!ha)
        return q + controller + ":9095" + q;
    else {
        auto group = hex_string_util::split(clusterGroup, ',');
        std::string servers = "";
        for (size_t i = 0 ; i < group.size() ; i++) {
            servers += q + group[i] + ":9095" + q;
            if (i + 1 < group.size())
                servers += ",";
        }

        return servers;
    }
}

std::string
StorPubIf(const std::string& storage)
{
    auto group = hex_string_util::split(storage, ',');
    return group[0];
}

std::string
StorClusterIf(const std::string& storage)
{
    auto group = hex_string_util::split(storage, ',');
    return group[group.size() - 1];
}

std::string
GetMgmtCidrIp(const std::string& mgmtCidr, int idx, const std::string& octet)
{
    std::vector<std::string> comps = hex_string_util::split(mgmtCidr, '/');

    if (comps.size() != 2)
        return "10.254.0.0/16";

    std::string netid = comps[0];
    std::string netMask = comps[1];

    int oIdx = 2;
    if (netMask == "8")
        oIdx = 1;

    std::vector<std::string> octets = hex_string_util::split(netid, '.');
    int octetNum = std::stoi(octets[oIdx]) + (idx * 128);

    std::string prefix;
    if (oIdx == 1)
        prefix = octets[0] + "." + std::to_string(octetNum) + "." + octets[2] + ".";
    else
        prefix = octets[0] + "." + octets[1] + "." + std::to_string(octetNum) + ".";

    std::string suffix;
    if (octet.length())
        suffix = octet;
    else {
        if (oIdx == 1)
            suffix = octets[3] + "/9";
        else
            suffix = octets[3] + "/17";
    }

    return prefix + suffix;
}

std::string
GetMgmtCidr(const std::string& mgmtCidr, int idx)
{
    return GetMgmtCidrIp(mgmtCidr, idx, "");
}

